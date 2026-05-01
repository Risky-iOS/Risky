import Foundation
import Logging

/// One captured line in the in-app log viewer. Independent of `swift-log`
/// so the SwiftUI view doesn't have to understand that library's types.
public struct LogEntry: Identifiable, Sendable {
  public let id = UUID()
  public let timestamp: Date
  public let severity: Severity
  public let message: String

  public init(timestamp: Date = .now, severity: Severity, message: String) {
    self.timestamp = timestamp
    self.severity = severity
    self.message = message
  }

  public enum Severity: Sendable {
    case debug
    case info
    case notice
    case warning
    case error
  }
}

public extension LogEntry.Severity {
  /// Maps a `swift-log` ``Logger/Level`` onto Risky’s coarser severity bucket.
  init(_ level: Logger.Level) {
    switch level {
      case .trace, .debug: self = .debug
      case .info: self = .info
      case .notice: self = .notice
      case .warning: self = .warning
      case .error, .critical: self = .error
    }
  }
}
