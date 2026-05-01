import Foundation

/// Describes which entity a ``Question`` is attached to.
public enum QuestionScope {
  /// Question lives on a specific pilot profile.
  case pilot(Pilot)
  /// Question lives on a specific aircraft.
  case aircraft(Aircraft)
  /// Question lives at the global (every-flight) level.
  case global(GlobalRiskSettings)
  /// Question is global but only applies to specific airports per ``AirportApplicability``.
  case airport(GlobalRiskSettings, applicability: AirportApplicability)
}
