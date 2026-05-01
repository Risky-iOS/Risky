import Foundation
import Logging

/// Retry policy for transient network operations.
///
/// Transient errors (network drops, 5xx, timeouts) are retried up to
/// ``maxAttempts`` total attempts with exponential backoff
/// (`baseDelay * 4^(attempt-1)`, capped at ``maxDelay``) plus
/// ±``jitterFraction`` random jitter. Permanent errors rethrow immediately.
public struct RetryPolicy: Sendable {
  public static let `default` = Self(
    maxAttempts: 4,
    baseDelay: .seconds(1),
    maxDelay: .seconds(60),
    jitterFraction: 0.3
  )

  public var maxAttempts: Int
  public var baseDelay: Duration
  public var maxDelay: Duration
  public var jitterFraction: Double

  public init(
    maxAttempts: Int,
    baseDelay: Duration,
    maxDelay: Duration,
    jitterFraction: Double
  ) {
    self.maxAttempts = maxAttempts
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
    self.jitterFraction = jitterFraction
  }
}

/// Runs `operation`, retrying on transient errors per `policy`.
///
/// A `RetryAfterError` overrides the backoff schedule with the server's
/// suggested delay (capped at `policy.maxDelay`). Permanent errors rethrow
/// immediately. On exhaustion the last error rethrows.
public func withRetries<T: Sendable>(
  _ policy: RetryPolicy = .default,
  logger: Logger,
  label: String,
  operation: @Sendable () async throws -> T
) async throws -> T {
  var attempt = 1
  while true {
    do {
      return try await operation()
    } catch {
      try Task.checkCancellation()
      let classification = classify(error)
      guard classification != .permanent, attempt < policy.maxAttempts else {
        throw error
      }
      let delay = backoffDelay(
        policy: policy,
        attempt: attempt,
        classification: classification
      )
      let detail =
        (error as? LocalizedError)?.failureReason ?? error.localizedDescription
      logger.notice(
        "Retrying “\(label)” (attempt \(attempt + 1)/\(policy.maxAttempts)) after \(delay): \(detail)"
      )
      try await Task.sleep(for: delay)
      attempt += 1
    }
  }
}

private func backoffDelay(
  policy: RetryPolicy,
  attempt: Int,
  classification: ErrorClassification
) -> Duration {
  if case .retryAfter(let suggested) = classification {
    return min(suggested, policy.maxDelay)
  }
  let factor = pow(4.0, Double(attempt - 1))
  let base = policy.baseDelay * factor
  let capped = min(base, policy.maxDelay)
  let jitterMultiplier =
    1.0 + Double.random(in: -policy.jitterFraction...policy.jitterFraction)
  return capped * jitterMultiplier
}

// MARK: - Classification

enum ErrorClassification: Equatable {
  case transient
  case retryAfter(Duration)
  case permanent
}

private let transientURLCodes: Set<URLError.Code> = [
  .timedOut,
  .networkConnectionLost,
  .notConnectedToInternet,
  .cannotConnectToHost,
  .cannotFindHost,
  .dnsLookupFailed,
  .resourceUnavailable,
  .secureConnectionFailed
]

private let transientHTTPStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

func classify(_ error: any Error) -> ErrorClassification {
  if let retry = error as? RetryAfterError {
    return .retryAfter(retry.delay)
  }
  if let httpError = error as? HTTPStatusError {
    if let retryAfter = httpError.retryAfter {
      return .retryAfter(retryAfter)
    }
    return transientHTTPStatuses.contains(httpError.statusCode)
      ? .transient : .permanent
  }
  if let urlError = error as? URLError {
    return transientURLCodes.contains(urlError.code) ? .transient : .permanent
  }
  let nsError = error as NSError
  if nsError.domain == NSURLErrorDomain {
    let code = URLError.Code(rawValue: nsError.code)
    return transientURLCodes.contains(code) ? .transient : .permanent
  }
  return .permanent
}

// MARK: - Error types

/// HTTP-status failure with optional `Retry-After` value parsed from the
/// response.
public struct HTTPStatusError: Error, Sendable, LocalizedError {
  public let statusCode: Int
  public let url: URL?
  public let retryAfter: Duration?

  public var errorDescription: String? {
    String(localized: "HTTP error.")
  }

  public var failureReason: String? {
    if let url {
      return String(
        localized: "HTTP \(statusCode, format: .number) for \(url.absoluteString)."
      )
    }
    return String(localized: "HTTP \(statusCode, format: .number).")
  }

  public init(statusCode: Int, url: URL?, retryAfter: Duration? = nil) {
    self.statusCode = statusCode
    self.url = url
    self.retryAfter = retryAfter
  }
}

/// Wraps a server-suggested retry delay (e.g. from a `Retry-After` header)
/// so the retry helper can use it instead of its own backoff schedule.
public struct RetryAfterError: Error, Sendable, LocalizedError {
  public let delay: Duration
  public let underlying: any Error

  public var errorDescription: String? {
    (underlying as? LocalizedError)?.errorDescription
      ?? String(localized: "Server requested retry.")
  }

  public var failureReason: String? {
    (underlying as? LocalizedError)?.failureReason
  }

  public init(delay: Duration, underlying: any Error) {
    self.delay = delay
    self.underlying = underlying
  }
}

// MARK: - User-Agent

/// `User-Agent` string identifying the Data Processor to public endpoints
/// (R2, FAA, OurAirports). Includes a contact URL when GitHub credentials
/// are configured, falling back to a generic placeholder otherwise.
public func politeUserAgent() -> String {
  let version =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ?? "0.0"
  let owner = CredentialsConfig[.githubOwner] ?? "anonymous"
  let repo = CredentialsConfig[.githubRepo] ?? "risky"
  return "Risky-Data-Processor/\(version) (+https://github.com/\(owner)/\(repo))"
}

// MARK: - Retry-After parsing

extension HTTPURLResponse {
  /// Parses the `Retry-After` header (per RFC 7231 §7.1.3) — either an
  /// integer count of seconds or an HTTP-date. Returns `nil` when absent
  /// or unparseable.
  public func retryAfter(now: Date = Date()) -> Duration? {
    guard
      let value =
        (value(forHTTPHeaderField: "Retry-After")
        ?? value(forHTTPHeaderField: "retry-after"))?
        .trimmingCharacters(in: .whitespaces),
      !value.isEmpty
    else { return nil }
    if let seconds = Int(value), seconds >= 0 {
      return .seconds(seconds)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    for format in [
      "EEE, dd MMM yyyy HH:mm:ss zzz",
      "EEEE, dd-MMM-yy HH:mm:ss zzz",
      "EEE MMM d HH:mm:ss yyyy"
    ] {
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        let interval = max(0, date.timeIntervalSince(now))
        return .seconds(interval)
      }
    }
    return nil
  }
}
