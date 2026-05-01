import Foundation
import SwiftData

/// A pilot profile. Holds personal calibration of stoplight thresholds and pilot-scoped questions.
@Model
public final class Pilot {
  /// Display name shown in pickers and summaries.
  public var name = ""
  /// Date at which the profile was created.
  public var createdAt = Date()
  /// Pilot’s ratings/privileges, used to scope eligible flight categories.
  public var rating = PilotRating.VFR

  /// Pilot-scoped questions seeded for this profile.
  @Relationship(deleteRule: .cascade, inverse: \Question._pilot)
  public var questions: [Question]? = []

  /// Flights authored by this pilot.
  @Relationship(deleteRule: .nullify, inverse: \Flight.pilot)
  public var flights: [Flight]? = []

  /// Creates a pilot profile with the given display name.
  public init(name: String) {
    self.name = name
  }
}
