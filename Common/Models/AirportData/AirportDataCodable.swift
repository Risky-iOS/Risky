import Foundation

/// Top-level container for the airport database produced by the Data Processor
/// and consumed by the Risky app.
///
/// Encoded as a binary property list and LZMA-compressed before distribution
/// via GitHub Releases. The Risky app downloads the latest cycle at runtime
/// and materializes individual ``AirportCodable`` records into SwiftData when
/// they are referenced by a flight.
public struct AirportDataCodable: Codable, Sendable {
  /// Cycle metadata for each upstream data source.
  public let cycles: DataCycles

  /// Date when the OurAirports CSV was last fetched, if used.
  public let ourAirportsLastUpdated: Date?

  /// Every airport in the database, sorted by identifier.
  public let airports: [AirportCodable]

  public init(
    cycles: DataCycles,
    ourAirportsLastUpdated: Date?,
    airports: [AirportCodable]
  ) {
    self.cycles = cycles
    self.ourAirportsLastUpdated = ourAirportsLastUpdated
    self.airports = airports
  }
}
