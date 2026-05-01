import Foundation
import SwiftData

/// A pilot-recorded squawk against a specific aircraft, used as risk input for upcoming flights.
@Model
public final class Squawk {
  /// Free-form description of the squawk.
  public var text = ""
  /// Pilot-assigned severity stoplight for this squawk.
  public var stoplight = Stoplight.yellow
  /// Date at which the squawk was filed.
  public var createdAt = Date()
  /// Aircraft this squawk is filed against.
  public var aircraft: Aircraft?

  /// Creates a squawk with the given text and stoplight severity.
  public init(text: String, stoplight: Stoplight) {
    self.text = text
    self.stoplight = stoplight
  }
}
