import Foundation
import RiskyCommon

/// Internal pipeline type used between source-specific processors and the
/// final ``AirportCodable``. Mutable, so each pipeline stage (CIFP, terrain
/// sampling) can attach derived data without rebuilding the whole record.
struct RawAirport {
  var identifier: String
  var name: String
  var latitude: Double
  var longitude: Double
  var elevationMeters: Double
  var isLighted: Bool
  var mountainousTerrain: Bool
  var runways: [RawRunway]
  var approaches: [ApproachCodable]
  let source: Source

  /// Source the record originated from. Used by the merger to prefer one
  /// source over another when the same identifier appears in both.
  enum Source { case nasr, ourAirports }
}

struct RawRunway {
  var identifier: String
  var isLighted: Bool
  var lengthMeters: Double
  var TORAMeters: Double
  var TODAMeters: Double
  var LDAMeters: Double
}

extension RawAirport {
  func toCodable() -> AirportCodable {
    AirportCodable(
      identifier: identifier,
      name: name,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
      isLighted: isLighted,
      mountainousTerrain: mountainousTerrain,
      runways: runways.map(\.toCodable),
      approaches: approaches
    )
  }
}

extension RawRunway {
  var toCodable: RunwayCodable {
    RunwayCodable(
      identifier: identifier,
      isLighted: isLighted,
      lengthMeters: lengthMeters,
      TORAMeters: TORAMeters,
      TODAMeters: TODAMeters,
      LDAMeters: LDAMeters
    )
  }
}
