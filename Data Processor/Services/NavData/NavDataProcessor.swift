import Foundation
import Logging
import RiskyCommon
import StreamingLZMA
import SwiftNASR

/// End-to-end orchestrator for one Data Processor run.
///
/// Pipeline:
/// 1. Download + parse FAA NASR for the requested cycle.
/// 2. Download + parse OurAirports CSVs.
/// 3. Download + parse FAA CIFP for the same cycle.
/// 4. Merge sources into a unified set of `RawAirport` records.
/// 5. For each airport, sample R2-hosted terrain and stamp the
///    mountainous-airport flag.
/// 6. Encode as `AirportDataCodable`, LZMA-compress, write locally.
/// 7. Optionally upload to GitHub Releases.
actor NavDataProcessor {
  /// Progress allocation across the run (out of 100):
  private static let nasrEnd = 30
  private static let ourAirportsEnd = 35
  private static let cifpEnd = 55
  private static let mergeEnd = 60
  private static let terrainEnd = 90
  private static let writeEnd = 95
  private static let uploadEnd = 100

  let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  private static func scale(_ value: Int, into range: Range<Int>) -> Int {
    let span = range.upperBound - range.lowerBound
    return range.lowerBound + Int(Double(value) / 100.0 * Double(span))
  }

  /// Runs the terrain mountainous-flag computation across `merged` with
  /// bounded concurrency. The catalog actor naturally serializes shared
  /// state (tile cache, region downloads), so excess parallelism just
  /// queues — `airportConcurrency = 8` is enough to keep the actor
  /// saturated and to overlap two parallel region downloads when airports
  /// span continents, without bloating the tile LRU.
  private static func runTerrainStage(
    merged: inout [RawAirport],
    sampler: TerrainSampler,
    onProgress: @escaping @Sendable (Stage, Int, Int) async -> Void
  ) async throws {
    let airportConcurrency = 8
    let total = merged.count
    struct Job: Sendable {
      let index: Int
      let latitude: Double
      let longitude: Double
      let elevationMeters: Double
    }
    let jobs: [Job] = merged.enumerated().map { offset, airport in
      Job(
        index: offset,
        latitude: airport.latitude,
        longitude: airport.longitude,
        elevationMeters: airport.elevationMeters
      )
    }

    try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
      var nextIndex = 0
      var completed = 0
      for _ in 0..<min(airportConcurrency, total) {
        let job = jobs[nextIndex]
        nextIndex += 1
        group.addTask {
          let isMountainous = await sampler.isMountainous(
            latitude: job.latitude,
            longitude: job.longitude,
            airportElevationMeters: job.elevationMeters
          )
          return (job.index, isMountainous)
        }
      }
      while let (index, isMountainous) = try await group.next() {
        merged[index].mountainousTerrain = isMountainous
        completed += 1
        if completed.isMultiple(of: 250) || completed == total {
          let f = Double(completed) / Double(total)
          let mapped =
            Self.mergeEnd
            + Int(f * Double(Self.terrainEnd - Self.mergeEnd))
          await onProgress(.terrain, mapped, 100)
          try Task.checkCancellation()
        }
        if nextIndex < total {
          let job = jobs[nextIndex]
          nextIndex += 1
          group.addTask {
            let isMountainous = await sampler.isMountainous(
              latitude: job.latitude,
              longitude: job.longitude,
              airportElevationMeters: job.elevationMeters
            )
            return (job.index, isMountainous)
          }
        }
      }
    }
  }

  /// Run the full pipeline. Returns the local URL of the compressed plist
  /// produced. The caller decides whether to upload.
  func run(
    cycle: SwiftNASR.Cycle,
    outputDirectory: URL,
    terrainCatalog: R2TerrainCatalog?,
    onProgress: @escaping @Sendable (Stage, Int, Int) async -> Void
  ) async throws -> Output {
    await onProgress(.starting, 0, 100)

    // 1. NASR
    await onProgress(.nasr, 0, 100)
    let nasrProcessor = NASRProcessor(logger: logger)
    let nasrResult = try await nasrProcessor.loadAirports(cycle: cycle) { c, _ in
      let mapped = Self.scale(c, into: 0..<Self.nasrEnd)
      await onProgress(.nasr, mapped, 100)
    }
    try Task.checkCancellation()

    // 2. OurAirports
    await onProgress(.ourAirports, Self.nasrEnd, 100)
    let ourAirports = OurAirportsLoader(logger: logger)
    let ourAirportsResult: (airports: [RawAirport], lastUpdated: Date)
    do {
      ourAirportsResult = try await ourAirports.loadAirports { c, t in
        let f = Double(c) / Double(t)
        let mapped =
          Self.nasrEnd + Int(f * Double(Self.ourAirportsEnd - Self.nasrEnd))
        await onProgress(.ourAirports, mapped, 100)
      }
    } catch {
      logger.warning(
        "OurAirports stage failed: \(error.localizedDescription) — continuing without supplemental data"
      )
      ourAirportsResult = ([], Date())
    }
    try Task.checkCancellation()

    // 3. CIFP
    await onProgress(.cifp, Self.ourAirportsEnd, 100)
    let cifpProcessor = CIFPProcessor(logger: logger)
    let cifpResult: ApproachLookup
    do {
      cifpResult = try await cifpProcessor.loadApproaches(cycle: cycle) { c, _ in
        let f = Double(c) / 100.0
        let mapped =
          Self.ourAirportsEnd
          + Int(f * Double(Self.cifpEnd - Self.ourAirportsEnd))
        await onProgress(.cifp, mapped, 100)
      }
    } catch {
      logger.warning(
        "CIFP stage failed: \(error.localizedDescription) — continuing without approach data"
      )
      cifpResult = ApproachLookup(byICAO: [:], cycle: nil)
    }
    try Task.checkCancellation()

    // 4. Merge
    await onProgress(.merge, Self.cifpEnd, 100)
    let merger = AirportMerger(logger: logger)
    var merged = merger.merge(
      nasr: nasrResult.airports,
      ourAirports: ourAirportsResult.airports,
      approaches: cifpResult
    )
    await onProgress(.merge, Self.mergeEnd, 100)
    try Task.checkCancellation()

    // 5. Terrain
    await onProgress(.terrain, Self.mergeEnd, 100)
    if let terrainCatalog {
      let sampler = TerrainSampler(catalog: terrainCatalog, logger: logger)
      try await Self.runTerrainStage(
        merged: &merged,
        sampler: sampler,
        onProgress: onProgress
      )
      await terrainCatalog.flushBoundingBoxCache()
    } else {
      logger.warning(
        "No terrain catalog provided — mountainous flag is false for every airport"
      )
    }
    await onProgress(.terrain, Self.terrainEnd, 100)
    try Task.checkCancellation()

    // 6. Write + compress
    await onProgress(.writing, Self.terrainEnd, 100)
    let cycles = DataCycles(nasr: nasrResult.cycle, cifp: cifpResult.cycle)
    let ourAirportsLastUpdated: Date? =
      ourAirportsResult.airports.isEmpty ? nil : ourAirportsResult.lastUpdated
    let codable = AirportDataCodable(
      cycles: cycles,
      ourAirportsLastUpdated: ourAirportsLastUpdated,
      airports: merged.map { $0.toCodable() }
    )

    let plistEncoder = PropertyListEncoder()
    plistEncoder.outputFormat = .binary
    let plistData = try plistEncoder.encode(codable)
    logger.notice("Encoded plist: \(plistData.count) bytes uncompressed")

    let compressed: Data
    do {
      compressed = try plistData.lzmaFileCompressed()
    } catch {
      throw error
    }
    logger.notice("LZMA-compressed plist: \(compressed.count) bytes")

    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    let cycleName = nasrResult.cycle.name
    let outputFile = outputDirectory.appending(path: "\(cycleName).plist.lzma")
    try compressed.write(to: outputFile)
    await onProgress(.writing, Self.writeEnd, 100)

    await onProgress(.completed, Self.uploadEnd, 100)

    return Output(
      file: outputFile,
      cycleName: cycleName,
      airportCount: merged.count,
      uncompressedBytes: plistData.count,
      compressedBytes: compressed.count,
      cycles: cycles,
      ourAirportsLastUpdated: ourAirportsLastUpdated
    )
  }

  enum Stage: Sendable {
    case starting
    case nasr
    case ourAirports
    case cifp
    case merge
    case terrain
    case writing
    case uploading
    case completed
  }

  struct Output: Sendable {
    let file: URL
    let cycleName: String
    let airportCount: Int
    let uncompressedBytes: Int
    let compressedBytes: Int
    let cycles: DataCycles
    let ourAirportsLastUpdated: Date?
  }
}
