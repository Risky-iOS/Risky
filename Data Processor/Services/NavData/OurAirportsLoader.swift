import Foundation
import Logging
import TabularData

/// Downloads and parses OurAirports CSVs to supplement the FAA NASR data
/// with international airports.
///
/// Adapted from SF50 TOLD's `OurAirportsLoader`. Risky's needs are much more
/// modest — no surface type, no displaced threshold, no width — so the
/// extracted record set is the small subset Risky's models care about.
struct OurAirportsLoader {
  private static let airportsURL = URL(
    string: "https://davidmegginson.github.io/ourairports-data/airports.csv"
  )!
  private static let runwaysURL = URL(
    string: "https://davidmegginson.github.io/ourairports-data/runways.csv"
  )!

  /// OurAirports surface descriptors that should disqualify a runway.
  private static let waterSurfaceTokens = ["water"]

  /// Minimum runway length in feet. Mirrors the NASR-side filter.
  private static let minimumRunwayLengthFt = 500

  /// Airport types to keep. Heliports and seaplane bases are excluded.
  private static let acceptedAirportTypes: Set<String> = [
    "small_airport", "medium_airport", "large_airport"
  ]

  let logger: Logger

  private static func parse(airportsCSV: Data, runwaysCSV: Data) throws -> [RawAirport] {
    let airportsFrame: DataFrame
    let runwaysFrame: DataFrame
    do {
      airportsFrame = try DataFrame(
        csvData: airportsCSV,
        options: CSVReadingOptions(hasHeaderRow: true)
      )
      runwaysFrame = try DataFrame(
        csvData: runwaysCSV,
        options: CSVReadingOptions(hasHeaderRow: true)
      )
    } catch {
      throw OurAirportsLoadError.csvParseFailed(
        reason: error.localizedDescription,
        line: nil
      )
    }

    let runwaysByAirport = groupRunways(runwaysFrame)
    var raw = [RawAirport]()
    raw.reserveCapacity(airportsFrame.rows.count)

    for row in airportsFrame.rows {
      guard
        let ident = row["ident", String.self],
        let type = row["type", String.self],
        Self.acceptedAirportTypes.contains(type),
        let name = row["name", String.self],
        let latitude = row["latitude_deg", Double.self],
        let longitude = row["longitude_deg", Double.self]
      else { continue }

      let elevationFt = Double(row["elevation_ft", Int.self] ?? 0)
      let icao = row["icao_code", String.self]
      let local = row["local_code", String.self] ?? ""
      let identifier = (icao?.isEmpty == false) ? icao! : (local.isEmpty ? ident : local)
      guard !identifier.isEmpty else { continue }

      let runways = runwaysByAirport[ident] ?? []
      guard !runways.isEmpty else { continue }

      let isLighted = runways.contains(where: \.isLighted)
      let airport = RawAirport(
        identifier: identifier,
        name: name,
        latitude: latitude,
        longitude: longitude,
        elevationMeters: elevationFt * 0.3048,
        isLighted: isLighted,
        mountainousTerrain: false,
        runways: runways,
        approaches: [],
        source: .ourAirports
      )
      raw.append(airport)
    }

    return raw
  }

  private static func groupRunways(_ frame: DataFrame) -> [String: [RawRunway]] {
    var grouped = [String: [RawRunway]]()
    for row in frame.rows {
      guard
        let airportIdent = row["airport_ident", String.self],
        let lengthFt = row["length_ft", Int.self],
        lengthFt >= Self.minimumRunwayLengthFt
      else { continue }

      let surface = row["surface", String.self] ?? ""
      let surfaceLowered = surface.lowercased()
      if Self.waterSurfaceTokens.contains(where: surfaceLowered.contains) {
        continue
      }

      let lengthMeters = Double(lengthFt) * 0.3048
      // OurAirports has a `lighted` 1/0 flag at the airport level via
      // `airports.csv` ("lighted") but only an implicit "has displaced
      // threshold" hint at the runway level. For lighting we err
      // conservatively: a non-zero `lighted` column on the runways
      // table flags the runway.
      let lightedFlag = (row["lighted", Int.self] ?? 0) != 0

      for prefix in ["le", "he"] {
        guard let ident = row["\(prefix)_ident", String.self], !ident.isEmpty
        else { continue }
        let runway = RawRunway(
          identifier: ident,
          isLighted: lightedFlag,
          lengthMeters: lengthMeters,
          TORAMeters: lengthMeters,
          TODAMeters: lengthMeters,
          LDAMeters: lengthMeters
        )
        grouped[airportIdent, default: []].append(runway)
      }
    }
    return grouped
  }

  private static func fetch(url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue(politeUserAgent(), forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw URLError(.cannotParseResponse)
    }
    guard (200..<300).contains(http.statusCode) else {
      throw HTTPStatusError(
        statusCode: http.statusCode,
        url: url,
        retryAfter: http.retryAfter()
      )
    }
    return data
  }

  func loadAirports(
    onProgress: (@Sendable (Int, Int) async -> Void)? = nil
  ) async throws -> (airports: [RawAirport], lastUpdated: Date) {
    await onProgress?(0, 2)
    logger.notice("Downloading OurAirports CSVs…")

    let airportsData: Data
    let runwaysData: Data
    do {
      let logger = self.logger
      async let a = withRetries(logger: logger, label: "OurAirports airports.csv") {
        try await Self.fetch(url: Self.airportsURL)
      }
      async let r = withRetries(logger: logger, label: "OurAirports runways.csv") {
        try await Self.fetch(url: Self.runwaysURL)
      }
      airportsData = try await a
      runwaysData = try await r
    } catch {
      throw OurAirportsLoadError.downloadFailed(underlying: error)
    }
    await onProgress?(1, 2)

    logger.notice("Parsing OurAirports CSVs…")
    let raw = try await Task.detached {
      try Self.parse(airportsCSV: airportsData, runwaysCSV: runwaysData)
    }.value
    await onProgress?(2, 2)

    logger.notice("Parsed \(raw.count) OurAirports records")
    return (airports: raw, lastUpdated: Date())
  }
}
