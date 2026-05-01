import Foundation

/// Cycle metadata for every data source bundled into the airport database.
public struct DataCycles: Codable, Sendable {
  /// FAA NASR (National Airspace System Resources) cycle. Required.
  public let nasr: CycleInfo

  /// FAA CIFP (Coded Instrument Flight Procedures) cycle. May be `nil` if
  /// the run skipped CIFP, e.g. during a partial regeneration.
  public let cifp: CycleInfo?

  public init(nasr: CycleInfo, cifp: CycleInfo?) {
    self.nasr = nasr
    self.cifp = cifp
  }
}

/// Effective and expiration window for a single data source cycle.
public struct CycleInfo: Codable, Sendable {
  /// Human-readable cycle name, e.g. "2501" for AIRAC cycle 2501.
  public let name: String

  /// First UTC instant at which this cycle is in effect.
  public let effective: Date

  /// First UTC instant at which this cycle is no longer in effect.
  public let expires: Date

  public init(name: String, effective: Date, expires: Date) {
    self.name = name
    self.effective = effective
    self.expires = expires
  }
}
