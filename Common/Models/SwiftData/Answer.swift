import Foundation
import SwiftData

/// A pilot’s response to a question, either entered directly or auto-filled from a data source.
@Model
public final class Answer {
  /// Date the answer was recorded or last updated.
  public var answeredAt = Date()
  /// How the answer arrived (manual entry vs. auto-fill).
  public var source = AnswerSource.manual
  /// Stoplight assigned to this answer based on the user’s calibration.
  public var stoplight: Stoplight?

  /// Question this answer is for.
  @Relationship(deleteRule: .nullify)
  public var question: Question?

  @Relationship(deleteRule: .nullify)
  var _chosenOption: QuestionOption?
  private var _numericValue: Double?

  /// Flight this answer is associated with.
  public var flight: Flight?

  /// Reconstructed answer value (choice or numeric bucket).
  public var value: AnswerValue? {
    guard let chosen = _chosenOption else { return nil }
    if let raw = _numericValue {
      return .bucket(value: raw, bucket: chosen)
    }
    return .choice(chosen)
  }

  /// Creates an answer for the given question and source.
  public init(question: Question, source: AnswerSource) {
    self.question = question
    self.source = source
  }

  /// Replaces the answer’s value, picking the underlying option/numeric value as appropriate.
  public func setValue(_ newValue: AnswerValue) {
    switch newValue {
      case .choice(let option):
        _chosenOption = option
        _numericValue = nil
      case let .bucket(raw, bucket):
        _chosenOption = bucket
        _numericValue = raw
    }
  }
}
