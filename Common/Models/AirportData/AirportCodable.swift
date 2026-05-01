import Foundation

/// A single airport record in the bundled airport database.
///
/// Mirrors the field set of ``RiskyCommon.Airport`` (the SwiftData model), but
/// stays as a plain `Codable` because the airport database lives in the app
/// bundle, not in SwiftData. When a pilot uses an airport in a flight, the
/// app copies the relevant fields into a SwiftData record.
public struct AirportCodable: Codable, Sendable {
  /// ICAO identifier when available, otherwise the FAA local identifier.
  /// Matches the SwiftData `Airport.identifier`.
  public let identifier: String

  /// Airport name, e.g. "San Francisco International".
  public let name: String

  /// Latitude in decimal degrees (WGS-84).
  public let latitude: Double

  /// Longitude in decimal degrees (WGS-84).
  public let longitude: Double

  /// Field elevation in meters above mean sea level.
  public let elevationMeters: Double

  /// Whether the airport has any lighted runway. (Used as a coarse
  /// "is lit at night" signal; per-runway detail is on ``RunwayCodable``.)
  public let isLighted: Bool

  /// Whether the surrounding terrain meets FAA Part 95 mountainous criteria
  /// (>3,000 ft elevation differential within 10 NM). Computed by the Data
  /// Processor against terrain rasters.
  public let mountainousTerrain: Bool

  /// Runways at this airport, one entry per runway end.
  public let runways: [RunwayCodable]

  /// Approaches at this airport. Each approach optionally references a
  /// specific runway via ``ApproachCodable/runwayIdentifier``; circling
  /// approaches (e.g. `VOR-A`, `RNV-F` at KASE) leave that field `nil`.
  public let approaches: [ApproachCodable]

  public init(
    identifier: String,
    name: String,
    latitude: Double,
    longitude: Double,
    elevationMeters: Double,
    isLighted: Bool,
    mountainousTerrain: Bool,
    runways: [RunwayCodable],
    approaches: [ApproachCodable]
  ) {
    self.identifier = identifier
    self.name = name
    self.latitude = latitude
    self.longitude = longitude
    self.elevationMeters = elevationMeters
    self.isLighted = isLighted
    self.mountainousTerrain = mountainousTerrain
    self.runways = runways
    self.approaches = approaches
  }
}
