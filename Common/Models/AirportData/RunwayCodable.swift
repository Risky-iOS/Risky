import Foundation

/// A single runway end (one direction) at an airport.
///
/// Mirrors the field set of ``RiskyCommon.Runway``. The Data Processor emits
/// one record per direction (e.g. "10R" and "28L" are separate records) so the
/// SwiftData model — which is itself per-direction — can be populated with a
/// straight field copy.
public struct RunwayCodable: Codable, Sendable {
  /// Runway designator, e.g. "01L", "28R", "36".
  public let identifier: String

  /// Whether this runway end has edge / centerline / threshold lighting.
  public let isLighted: Bool

  /// Total physical runway length in meters.
  public let lengthMeters: Double

  /// Takeoff Run Available in meters.
  public let TORAMeters: Double

  /// Takeoff Distance Available in meters.
  public let TODAMeters: Double

  /// Landing Distance Available in meters.
  public let LDAMeters: Double

  public init(
    identifier: String,
    isLighted: Bool,
    lengthMeters: Double,
    TORAMeters: Double,
    TODAMeters: Double,
    LDAMeters: Double
  ) {
    self.identifier = identifier
    self.isLighted = isLighted
    self.lengthMeters = lengthMeters
    self.TORAMeters = TORAMeters
    self.TODAMeters = TODAMeters
    self.LDAMeters = LDAMeters
  }
}
