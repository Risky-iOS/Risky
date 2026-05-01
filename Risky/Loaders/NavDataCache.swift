import Foundation
import RiskyCommon
import os

/// On-disk cache for the airport database, living in the shared App Group
/// container so widgets and the main app see the same payload.
///
/// Layout under `{appGroup}/AviationData/`:
///
/// ```
/// payload.plist          // decompressed binary plist of AirportDataCodable
/// local-manifest.json    // small Codable describing what payload.plist holds
/// ```
///
/// The cache is split so the freshness probe (`loadLocalManifest()`) is
/// fast — it does not have to deserialize the multi-MB payload.
struct NavDataCache: Sendable {
  /// Bumped whenever the on-disk layout or `LocalManifest` shape changes
  /// in a way that should force a re-download.
  static let schemaVersion = 1

  static let shared = Self()

  private static let directoryName = "AviationData"
  private static let payloadFileName = "payload.plist"
  private static let localManifestFileName = "local-manifest.json"

  private let logger = Logger(subsystem: "codes.tim.Risky", category: "NavDataCache")

  /// URL of the directory that holds the cache files. Returns `nil` if the
  /// app group isn't reachable (which would indicate a misconfigured
  /// entitlement).
  var directoryURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appending(path: Self.directoryName)
  }

  /// Reads the on-disk local manifest. Returns `nil` if the cache is
  /// empty, the file is missing, or the file is unreadable / unparseable
  /// (in which case it logs and treats the cache as empty so the loader
  /// will re-download).
  func loadLocalManifest() -> LocalManifest? {
    guard let url = directoryURL?.appending(path: Self.localManifestFileName),
      FileManager.default.fileExists(atPath: url.path)
    else { return nil }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(LocalManifest.self, from: data)
    } catch {
      logger.error("Failed to read local manifest: \(error.localizedDescription)")
      return nil
    }
  }

  /// Writes the decompressed binary plist and a fresh local manifest atomically.
  func persist(decompressedPayload: Data, manifest: AviationDataManifest) throws {
    guard let directoryURL else { throw Errors.appGroupUnavailable }

    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    let payloadURL = directoryURL.appending(path: Self.payloadFileName)
    try decompressedPayload.write(to: payloadURL, options: .atomic)

    let local = LocalManifest(
      schemaVersion: Self.schemaVersion,
      cycleName: manifest.latestCycleName,
      expires: manifest.cycles.nasr.expires,
      downloadedAt: Date(),
      cycles: manifest.cycles
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let manifestData = try encoder.encode(local)
    let manifestURL = directoryURL.appending(path: Self.localManifestFileName)
    try manifestData.write(to: manifestURL, options: .atomic)
  }

  /// Loads and decodes the cached payload. Used by future consumers; the
  /// loader itself doesn't call this.
  func loadPayload() throws -> AirportDataCodable {
    guard let url = directoryURL?.appending(path: Self.payloadFileName),
      FileManager.default.fileExists(atPath: url.path)
    else { throw Errors.payloadMissing }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return try PropertyListDecoder().decode(AirportDataCodable.self, from: data)
  }

  /// Persisted snapshot of what's currently in the on-disk cache.
  ///
  /// Stored alongside ``NavDataCache/payloadFileName`` so cache directory
  /// listings stay self-describing and freshness checks don't need to
  /// decode the payload.
  struct LocalManifest: Codable, Sendable {
    /// Schema version bumped whenever the cache layout changes in a way
    /// that requires a re-download. See ``NavDataCache/schemaVersion``.
    let schemaVersion: Int
    /// AIRAC cycle name of the cached payload, e.g. `"2501"`.
    let cycleName: String
    /// First UTC instant at which the payload's NASR cycle is no longer
    /// in effect. The freshness probe compares this against `Date()`.
    let expires: Date
    /// Time at which the loader wrote this entry.
    let downloadedAt: Date
    /// Cycle metadata copied from the published manifest.
    let cycles: DataCycles
  }

  enum Errors: LocalizedError {
    case appGroupUnavailable
    case payloadMissing

    var errorDescription: String? {
      String(localized: "Couldn’t access airport data.")
    }

    var failureReason: String? {
      switch self {
        case .appGroupUnavailable:
          return String(localized: "The shared app group container is not available.")
        case .payloadMissing:
          return String(localized: "No airport data has been downloaded yet.")
      }
    }
  }
}
