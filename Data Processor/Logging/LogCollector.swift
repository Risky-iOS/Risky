import Foundation
import Logging

/// In-memory ring buffer of log entries, populated by a `swift-log` handler.
///
/// The Data Processor pushes log records both to stdout (via the standard
/// `StreamLogHandler`) and into this collector, which the SwiftUI ``LogViewer``
/// renders. Capacity defaults to 5,000 lines — enough to capture a full run,
/// small enough to keep memory bounded.
public actor LogCollector {
  /// Process-wide collector that the bootstrap routes records into.
  public static let shared = LogCollector()

  /// Default ring-buffer capacity in number of entries.
  public static let defaultCapacity = 5_000

  private let capacity: Int
  private var entries: [LogEntry] = []
  private var observers: [@Sendable ([LogEntry]) -> Void] = []

  /// Creates a collector with the given ring-buffer capacity.
  public init(capacity: Int = LogCollector.defaultCapacity) {
    self.capacity = capacity
  }

  /// Appends an entry, trimming the oldest entries to keep within capacity, and notifies observers.
  public func append(_ entry: LogEntry) {
    entries.append(entry)
    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
    let snapshot = entries
    for observer in observers { observer(snapshot) }
  }

  /// Returns the current contents of the buffer.
  public func snapshot() -> [LogEntry] { entries }

  /// Registers a sink that receives a snapshot on every append (and immediately for backfill).
  public func observe(_ block: @escaping @Sendable ([LogEntry]) -> Void) {
    observers.append(block)
    block(entries)
  }
}

/// `swift-log` handler that mirrors records into ``LogCollector``.
public struct CollectingLogHandler: LogHandler {
  public var metadata: Logger.Metadata = [:]
  public var logLevel: Logger.Level = .info

  private let collector: LogCollector
  private let label: String

  public init(label: String, collector: LogCollector = .shared) {
    self.label = label
    self.collector = collector
  }

  public func log(event: LogEvent) {
    let entry = LogEntry(
      severity: .init(event.level),
      message: event.message.description
    )
    Task { await collector.append(entry) }
  }

  public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }
}

/// One-time bootstrap: pipe `swift-log` to both stdout and ``LogCollector``.
public enum LoggingBootstrap {
  nonisolated(unsafe) private static var hasBootstrapped = false
  private static let lock = NSLock()

  /// Bootstraps the logging system, idempotently. Subsequent calls are no-ops.
  public static func runOnce(level: Logger.Level = .info) {
    lock.lock()
    defer { lock.unlock() }
    guard !hasBootstrapped else { return }
    hasBootstrapped = true

    LoggingSystem.bootstrap { label in
      var stream = StreamLogHandler.standardOutput(label: label)
      stream.logLevel = level
      var collecting = CollectingLogHandler(label: label)
      collecting.logLevel = level
      return MultiplexLogHandler([stream, collecting])
    }
  }
}
