import Foundation

/// Lightweight metadata file the Data Processor publishes alongside each
/// airport-data payload.
///
/// The Risky iOS app fetches this manifest on launch (or when re-checking
/// freshness) so it can discover the latest cycle without downloading the
/// multi-MB compressed plist itself, then compares ``latestCycleName`` and
/// ``cycles.nasr.expires`` against its locally cached copy.
public struct AviationDataManifest: Codable, Sendable {
  /// Name of the latest published cycle, e.g. `"2501"`.
  public let latestCycleName: String

  /// Repository-relative path to the compressed payload for this cycle,
  /// e.g. `"risky-data/2501.plist.lzma"`. Suitable for appending to the
  /// raw GitHub base URL for the data repository.
  public let payloadPath: String

  /// Cycle metadata for every data source bundled into the payload.
  public let cycles: DataCycles

  /// Timestamp of the OurAirports CSV included in the payload, when used.
  public let ourAirportsLastUpdated: Date?

  /// Time at which the Data Processor produced this manifest.
  public let generatedAt: Date

  public init(
    latestCycleName: String,
    payloadPath: String,
    cycles: DataCycles,
    ourAirportsLastUpdated: Date?,
    generatedAt: Date
  ) {
    self.latestCycleName = latestCycleName
    self.payloadPath = payloadPath
    self.cycles = cycles
    self.ourAirportsLastUpdated = ourAirportsLastUpdated
    self.generatedAt = generatedAt
  }
}
