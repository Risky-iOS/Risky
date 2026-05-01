import Foundation
import Logging
import SwiftCIFP
import SwiftNASR
import RiskyCommon

/// Downloads and parses an FAA CIFP cycle, then attaches per-runway
/// approaches to a set of ``RawAirport`` records produced by the NASR /
/// OurAirports stages.
///
/// Risky's `Approach` schema is much smaller than SF50 TOLD's: only the
/// approach type and per-category minimums. CIFP itself does not publish
/// minimums (those live in the Terminal Procedure Publication), so the
/// minimums array is empty for v1 — pilots fill it in later.
struct CIFPProcessor {
  private static let cifpURLTemplate = "https://aeronav.faa.gov/Upload_313-d/cifp/CIFP_%@.zip"

  /// Progress allocation within CIFP processing (out of 100):
  /// - Download:  0..<30
  /// - Parse:    30..<90
  /// - Link:     90..<100
  private static let downloadProgressEnd = 30
  private static let parseProgressEnd = 90
  private static let linkProgressEnd = 100

  let logger: Logger

  // MARK: - Type methods

  private static func makeRequest(for url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(politeUserAgent(), forHTTPHeaderField: "User-Agent")
    return request
  }

  private static func buildLookup(
    from data: CIFPData,
    logger: Logger
  ) async -> [String: [ApproachCodable]] {
    var byICAO: [String: [ApproachCodable]] = [:]

    let airportMap = await data.airports
    for (icao, airport) in airportMap {
      // Dedupe by (type, runway) — multiple legs/transitions of the
      // same approach show up as separate `Approach` records.
      var seen: Set<DedupKey> = []
      var approaches: [ApproachCodable] = []

      for approach in airport.approaches {
        guard approach.approachType != .transition,
          approach.approachType != .missedApproach
        else { continue }

        guard let mapped = mapApproachType(approach.approachType) else {
          let typeName = approach.approachType.description
          logger.debug(
            "Dropping approach \(approach.identifier) at \(icao): type \(typeName) not in Risky's set"
          )
          continue
        }

        let runwayID = runwayIdentifier(from: approach.identifier)
        let key = DedupKey(type: mapped, runwayIdentifier: runwayID)
        guard seen.insert(key).inserted else { continue }
        approaches.append(
          ApproachCodable(type: mapped, runwayIdentifier: runwayID, minimums: [])
        )
      }

      if !approaches.isEmpty {
        byICAO[icao] = approaches.sorted { lhs, rhs in
          let lhsRwy = lhs.runwayIdentifier ?? ""
          let rhsRwy = rhs.runwayIdentifier ?? ""
          if lhsRwy != rhsRwy { return lhsRwy < rhsRwy }
          return lhs.type.rawValue < rhs.type.rawValue
        }
      }
    }

    return byICAO
  }

  /// Extracts the runway identifier (e.g. `"19L"`, `"22"`) from a CIFP
  /// approach identifier (e.g. `"I19L"`, `"R22-Y"`, `"R10RY"`, `"H19-Z"`).
  /// Returns `nil` for circling approaches (`"VOR-A"`, `"RNV-F"`) and
  /// other identifiers that don't reference a specific runway.
  ///
  /// Standard pattern: type-letter + 2-digit-runway + optional L/R/C
  /// designator + optional `-` + optional multiple-indicator letter.
  /// The type-letter is permissive (any uppercase) since CIFP uses many
  /// letters (I=ILS, L=LOC, R=RNAV, V=VOR, N=NDB, H=RNP, X=LDA, etc.);
  /// the digit-anchored runway match is what filters out non-runway
  /// procedures like `"VOR-A"`.
  private static func runwayIdentifier(from approachIdentifier: String) -> String? {
    let regex = #/^[A-Z](\d{2}[LRC]?)-?[A-Z]?$/#
    guard let match = approachIdentifier.wholeMatch(of: regex) else { return nil }
    return String(match.output.1)
  }

  private static func mapApproachType(
    _ cifp: SwiftCIFP.ApproachType
  ) -> RiskyCommon.ApproachType? {
    switch cifp {
      case .ils, .igs: .ILS
      case .localizerOnly, .localizerBackcourse: .LOC
      case .rnav, .rnpAR: .RNAV
      case .vor, .vorDME, .vorTAC: .VOR
      case .ndb, .ndbDME: .NDB
      case .gps, .fms: .GPS
      case .lda: .LDA
      case .gls, .mls, .mlsTypeA, .mlsTypeBC, .tacan, .sdf,
        .transition, .missedApproach:
        nil
    }
  }

  // MARK: - Instance methods

  /// Downloads CIFP for the given cycle, parses it, and returns a lookup
  /// map keyed by `(airportICAO, runwayID)` with the corresponding
  /// `[ApproachCodable]`.
  func loadApproaches(
    cycle: SwiftNASR.Cycle,
    onProgress: (@Sendable (Int, Int) async -> Void)? = nil
  ) async throws -> ApproachLookup {
    await onProgress?(0, 100)

    let dateString = formatCIFPDate(cycle)
    guard let cifpURL = URL(string: String(format: Self.cifpURLTemplate, dateString)) else {
      throw CIFPError.downloadFailed(
        underlying: URLError(.badURL)
      )
    }

    logger.notice("Downloading CIFP zip from \(cifpURL.absoluteString)…")
    let zipData: Data
    do {
      let request = Self.makeRequest(for: cifpURL)
      zipData = try await withRetries(logger: logger, label: "CIFP zip") {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          throw URLError(.cannotParseResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
          throw HTTPStatusError(
            statusCode: http.statusCode,
            url: cifpURL,
            retryAfter: http.retryAfter()
          )
        }
        return data
      }
    } catch {
      throw CIFPError.downloadFailed(underlying: error)
    }
    await onProgress?(Self.downloadProgressEnd, 100)
    try Task.checkCancellation()

    let cifpData = try await extractCIFP(from: zipData)

    logger.notice("Parsing CIFP…")
    let cifp: CIFP
    do {
      cifp = try CIFP(
        data: cifpData,
        progressHandler: { progress in
          self.observeProgress(
            progress,
            mappingTo: Self.downloadProgressEnd..<Self.parseProgressEnd,
            onProgress: onProgress
          )
        },
        errorCallback: { error, lineNumber in
          self.logger.debug(
            "CIFP parse error at line \(lineNumber.map { "\($0)" } ?? "?"): \(error)"
          )
        }
      )
    } catch {
      throw CIFPError.parseFailed(underlying: error)
    }
    await onProgress?(Self.parseProgressEnd, 100)
    try Task.checkCancellation()

    logger.notice("Linking CIFP…")
    let linked = await cifp.linked()
    await onProgress?(Self.linkProgressEnd, 100)

    let lookup = await Self.buildLookup(from: linked, logger: logger)
    let cycleInfo = makeCycleInfo(from: cifp.cycle)

    logger.notice("Built CIFP approach lookup for \(lookup.count) airports")
    return ApproachLookup(byICAO: lookup, cycle: cycleInfo)
  }

  private func formatCIFPDate(_ cycle: SwiftNASR.Cycle) -> String {
    let yearSuffix = cycle.year % 100
    return String(format: "%02d%02d%02d", yearSuffix, cycle.month, cycle.day)
  }

  private func makeCycleInfo(from cifpCycle: SwiftCIFP.Cycle?) -> CycleInfo? {
    guard let cifpCycle else { return nil }
    return CycleInfo(
      name: "\(cifpCycle)",
      effective: cifpCycle.effectiveDate ?? Date.distantPast,
      expires: cifpCycle.expirationDate ?? Date.distantFuture
    )
  }

  private func observeProgress(
    _ progress: Progress,
    mappingTo range: Range<Int>,
    onProgress: (@Sendable (Int, Int) async -> Void)?
  ) {
    guard let onProgress else { return }
    let span = range.upperBound - range.lowerBound
    let observation = progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
      let mapped = range.lowerBound + Int(Double(span) * progress.fractionCompleted)
      Task.detached { await onProgress(mapped, 100) }
    }
    Task { await NASRProgressObservations.shared.add(observation) }
  }

  private func extractCIFP(from zipData: Data) async throws -> Data {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let zipFile = tempDir.appending(path: "cifp.zip")
    try zipData.write(to: zipFile)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-o", "-q", zipFile.path, "-d", tempDir.path]
    let pipe = Pipe()
    process.standardError = pipe

    do {
      try process.run()
      await Task.detached { process.waitUntilExit() }.value
    } catch {
      throw CIFPError.parseFailed(underlying: error)
    }

    guard process.terminationStatus == 0 else {
      let errorOutput =
        String(
          data: pipe.fileHandleForReading.readDataToEndOfFile(),
          encoding: .utf8
        ) ?? ""
      throw CIFPError.parseFailed(
        underlying: NSError(
          domain: "CIFP",
          code: Int(process.terminationStatus),
          userInfo: [NSLocalizedDescriptionKey: "unzip failed: \(errorOutput)"]
        )
      )
    }

    let cifpFile = tempDir.appending(path: "FAACIFP18")
    if FileManager.default.fileExists(atPath: cifpFile.path) {
      return try Data(contentsOf: cifpFile)
    }

    // Fall back to walking the directory if the file name differs.
    if let entries = try? FileManager.default.contentsOfDirectory(
      at: tempDir,
      includingPropertiesForKeys: nil
    ) {
      for url in entries where url.lastPathComponent.hasPrefix("FAACIFP") {
        return try Data(contentsOf: url)
      }
    }

    throw CIFPError.parseFailed(
      underlying: NSError(
        domain: "CIFP",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "FAACIFP file not found in archive"]
      )
    )
  }

  private struct DedupKey: Hashable {
    let type: RiskyCommon.ApproachType
    let runwayIdentifier: String?
  }
}

/// Result of a successful CIFP run: per-airport approach list plus cycle
/// metadata. Each ``ApproachCodable`` carries an optional
/// ``ApproachCodable/runwayIdentifier`` linking it to a specific runway;
/// circling approaches leave that field `nil`.
struct ApproachLookup: Sendable {
  /// `byICAO[airportICAO] -> [ApproachCodable]`.
  let byICAO: [String: [ApproachCodable]]
  let cycle: CycleInfo?

  var count: Int { byICAO.count }
}
