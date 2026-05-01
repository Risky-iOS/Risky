import Foundation
import Logging

/// GET-only client for the R2 bucket where SF50 TOLD's DownloadNASR has
/// already published terrain region files. Risky's Data Processor consumes
/// those files to compute the mountainous-airport flag — it never writes to
/// R2 itself, so the public URL is sufficient.
///
/// Retries transient errors with exponential backoff, identifies itself with
/// a polite `User-Agent`, and caps concurrent multi-GB region downloads to
/// keep the public bucket healthy.
actor R2Downloader {
  /// Polite cap on concurrent large-file downloads. The small-file path
  /// (``data(at:)``) is uncapped because manifest fetches are tiny.
  private static let regionConcurrencyLimit = 2

  private let publicURL: URL
  private let logger: Logger
  private let session: URLSession
  private let userAgent: String
  private let retryPolicy: RetryPolicy

  private var inFlightLargeDownloads = 0
  private var largeDownloadWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    publicURL: URL,
    logger: Logger,
    session: URLSession? = nil,
    userAgent: String? = nil,
    retryPolicy: RetryPolicy = .default
  ) {
    self.publicURL = publicURL
    self.logger = logger
    self.session = session ?? Self.makeDefaultSession()
    self.userAgent = userAgent ?? politeUserAgent()
    self.retryPolicy = retryPolicy
  }

  /// Convenience initializer pulling the public URL from credentials, or
  /// falling back to ``CredentialsConfig/defaultTerrainPublicURL``.
  init(logger: Logger) throws {
    let raw =
      CredentialsConfig[.terrainPublicURL]
      ?? CredentialsConfig.defaultTerrainPublicURL
    guard let url = URL(string: raw.hasSuffix("/") ? raw : raw + "/") else {
      throw CredentialsError.missing(key: CredentialsConfig.Key.terrainPublicURL.rawValue)
    }
    self.init(publicURL: url, logger: logger)
  }

  // MARK: - Type methods

  private static func makeDefaultSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    // Multi-GB region downloads can stall briefly between TCP packets;
    // the default 60s request-timeout is too tight. Allow a long pause
    // (10 min) before declaring an inactivity failure, and a generous
    // wall-clock cap (1 hour) for the whole transfer.
    config.timeoutIntervalForRequest = 600
    config.timeoutIntervalForResource = 3_600
    config.waitsForConnectivity = true
    return URLSession(configuration: config)
  }

  private static func checkSuccess(response: URLResponse, url: URL) throws {
    guard let http = response as? HTTPURLResponse else {
      throw URLError(.cannotParseResponse)
    }
    guard !(200..<300).contains(http.statusCode) else { return }
    throw HTTPStatusError(
      statusCode: http.statusCode,
      url: url,
      retryAfter: http.retryAfter()
    )
  }

  // MARK: - Instance methods

  /// Download the file at `objectKey` (relative to the public URL) into
  /// memory. Retries transient errors per the configured policy.
  func data(at objectKey: String) async throws -> Data {
    let url = publicURL.appending(path: objectKey.trimmingPrefix("/"))
    let request = makeRequest(url: url)
    let session = self.session
    let logger = self.logger
    return try await withRetries(retryPolicy, logger: logger, label: "GET \(url.lastPathComponent)")
    {
      logger.debug("R2 GET \(url.absoluteString)")
      let (data, response) = try await session.data(for: request)
      try Self.checkSuccess(response: response, url: url)
      return data
    }
  }

  /// Download the file at `objectKey` into a temporary file, returning the
  /// local URL. Use when the payload is large enough that you'd rather not
  /// hold it all in memory. Concurrency-limited per
  /// ``regionConcurrencyLimit`` and retried on transient failures.
  func downloadToTemporaryFile(
    objectKey: String,
    onProgress: (@Sendable (Double) async -> Void)? = nil
  ) async throws -> URL {
    let url = publicURL.appending(path: objectKey.trimmingPrefix("/"))
    let request = makeRequest(url: url)
    let session = self.session
    let logger = self.logger

    await acquireLargeDownloadSlot()
    defer { Task { self.releaseLargeDownloadSlot() } }

    let destination = try await withRetries(
      retryPolicy,
      logger: logger,
      label: "DOWNLOAD \(url.lastPathComponent)"
    ) {
      logger.debug("R2 GET (to file) \(url.absoluteString)")
      let (tempURL, response) = try await session.download(for: request)
      do {
        try Self.checkSuccess(response: response, url: url)
      } catch {
        try? FileManager.default.removeItem(at: tempURL)
        throw error
      }
      let dest = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension(url.pathExtension)
      do {
        try FileManager.default.moveItem(at: tempURL, to: dest)
      } catch {
        try? FileManager.default.removeItem(at: tempURL)
        throw error
      }
      return dest
    }
    await onProgress?(1.0)
    return destination
  }

  private func makeRequest(url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    return request
  }

  private func acquireLargeDownloadSlot() async {
    if inFlightLargeDownloads < Self.regionConcurrencyLimit {
      inFlightLargeDownloads += 1
      return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      largeDownloadWaiters.append(continuation)
    }
    inFlightLargeDownloads += 1
  }

  private func releaseLargeDownloadSlot() {
    inFlightLargeDownloads -= 1
    if !largeDownloadWaiters.isEmpty {
      let next = largeDownloadWaiters.removeFirst()
      next.resume()
    }
  }
}

private extension String {
  func trimmingPrefix(_ prefix: String) -> String {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
  }
}
