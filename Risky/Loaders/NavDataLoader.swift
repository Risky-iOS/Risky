import Foundation
import RiskyCommon
import StreamingLZMA
import os

/// Downloads, decompresses, and caches the airport database from the
/// `Risky-iOS/Aviation-Data` GitHub repo.
///
/// Modeled after SF50 TOLD's `NavDataLoader` but adapted for Risky's disk
/// cache: the decoded payload lives in the App Group container rather than
/// SwiftData, so the pipeline has two visible stages (Download, Decompress)
/// instead of three.
///
/// ## Pipeline
///
/// 1. **Manifest probe.** Fetch `risky-data/manifest.json` to discover the
///    latest published cycle.
/// 2. **Download payload.** Stream `{manifest.payloadPath}` with
///    `URLSession.bytes`, reporting progress every 8 KB.
/// 3. **Decompress.** LZMA-decompress in memory.
/// 4. **Persist.** Hand the decompressed plist to ``NavDataCache`` for
///    atomic on-disk write alongside a local manifest.
///
/// ## Progress
///
/// Poll the ``state`` property to track loading progress. Mirrors SF50
/// TOLD's polling pattern (the view model spawns a 0.25 s background poll
/// while a load is active).
actor NavDataLoader {
  private static let baseURL = URL(string: "https://github.com/Risky-iOS/Aviation-Data/raw/main/")!
  private static let manifestPath = "risky-data/manifest.json"

  var state: State = .idle

  private let cache: NavDataCache
  private let logger = Logger(subsystem: "codes.tim.Risky", category: "NavDataLoader")

  init(cache: NavDataCache = .shared) {
    self.cache = cache
  }

  func load() async throws -> LoadResult {
    state = .downloading(progress: 0)

    let manifest = try await fetchManifest()
    let payloadURL = Self.baseURL.appending(path: manifest.payloadPath)
    let compressed = try await downloadPayload(from: payloadURL) { progress in
      self.state = .downloading(progress: progress)
    }

    state = .extracting(progress: nil)
    let decompressed = try compressed.lzmaFileDecompressed()
    logger.notice("Decompressed payload: \(decompressed.count) bytes")

    try cache.persist(decompressedPayload: decompressed, manifest: manifest)
    state = .finished

    return LoadResult(manifest: manifest)
  }

  private func fetchManifest() async throws -> AviationDataManifest {
    let url = Self.baseURL.appending(path: Self.manifestPath)
    return try await withRetry(logger: logger, label: "manifest") {
      let session = URLSession(configuration: .ephemeral)
      let (data, response) = try await session.data(from: url)
      guard let response = response as? HTTPURLResponse else {
        throw Errors.badResponse(response)
      }
      if response.statusCode == 404 { throw Errors.manifestUnavailable }
      guard response.statusCode == 200 else { throw Errors.badResponse(response) }

      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(AviationDataManifest.self, from: data)
    }
  }

  private func downloadPayload(
    from url: URL,
    progress: (Float) -> Void
  ) async throws -> Data {
    try await withRetry(logger: logger, label: "payload") {
      let session = URLSession(configuration: .ephemeral)
      let (bytes, response) = try await session.bytes(from: url)
      guard let response = response as? HTTPURLResponse else {
        throw Errors.badResponse(response)
      }
      if response.statusCode == 404 { throw Errors.cycleNotAvailable }
      guard response.statusCode == 200 else { throw Errors.badResponse(response) }

      let expectedLength = response.expectedContentLength
      var compressed = Data(capacity: max(0, Int(expectedLength)))
      for try await byte in bytes {
        compressed.append(byte)
        if compressed.count.isMultiple(of: 8192) {
          if expectedLength > 0 {
            progress(Float(Double(compressed.count) / Double(expectedLength)))
          }
        }
      }

      return compressed
    }
  }

  /// Current state of the loading process.
  enum State: Sendable, Equatable {
    case idle
    case downloading(progress: Float?)
    case extracting(progress: Float?)
    case finished
  }

  /// Errors that can occur during data loading.
  enum Errors: LocalizedError {
    /// The latest payload referenced by the manifest is no longer reachable.
    case cycleNotAvailable
    /// `manifest.json` could not be fetched from the data repo.
    case manifestUnavailable
    /// The server returned an unexpected response.
    case badResponse(_ response: URLResponse)

    var errorDescription: String? {
      String(localized: "Couldn’t download airport data.")
    }

    var failureReason: String? {
      switch self {
        case .cycleNotAvailable:
          return String(
            localized: "The published airport data is unavailable. Try again later."
          )
        case .manifestUnavailable:
          return String(
            localized: "Couldn’t look up the latest airport data version."
          )
        case .badResponse(let response):
          let code = (response as? HTTPURLResponse)?.statusCode ?? 0
          return String(
            localized: "Received HTTP error \(code, format: .number) when downloading."
          )
      }
    }

    var recoverySuggestion: String? {
      String(localized: "Check your network connection and try again.")
    }
  }

  /// Loaded data, returned from ``NavDataLoader/load()`` so callers can
  /// react to a successful refresh without re-reading the cache.
  struct LoadResult: Sendable {
    let manifest: AviationDataManifest
  }
}
