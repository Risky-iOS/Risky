import Foundation
import SwiftData

/// One choice/bucket for a ``Question``. Carries the pilot’s stoplight calibration for that option.
@Model
public final class QuestionOption {
  /// Display label for the option.
  public var label = ""
  /// Sort order within the question’s option list.
  public var sortOrder = 0
  /// Pilot-assigned stoplight when this option is selected.
  public var stoplight: Stoplight?

  private var _lowerBound: Double?
  private var _upperBound: Double?

  /// Question this option belongs to.
  public var question: Question?

  /// Answers that picked this option.
  @Relationship(deleteRule: .nullify, inverse: \Answer._chosenOption)
  public var answers: [Answer]? = []

  /// nil for choice/yesNo options; (lower, upper) tuple for numericBuckets options.
  public var bounds: (lower: Double?, upper: Double?)? {
    get {
      guard _lowerBound != nil || _upperBound != nil else { return nil }
      return (_lowerBound, _upperBound)
    }
    set {
      _lowerBound = newValue?.lower
      _upperBound = newValue?.upper
    }
  }

  /// Creates an option with the given label, sort order, and optional numeric bounds.
  public init(
    label: String,
    sortOrder: Int,
    bounds: (lower: Double?, upper: Double?)? = nil
  ) {
    self.label = label
    self.sortOrder = sortOrder
    self.bounds = bounds
  }
}
