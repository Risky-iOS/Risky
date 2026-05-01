import Foundation
import SwiftData

/// A risk question that maps a yes/no, multiple-choice, or numeric-bucket answer to a stoplight.
@Model
public final class Question {
  /// User-facing prompt for the question.
  public var title = ""
  /// Optional clarifying detail shown beneath the title.
  public var subtitle: String?
  /// PAVE category this question belongs to.
  public var category = RiskCategory.pilot
  /// Sort order within its scope.
  public var sortOrder = 0

  var _kind = "yesNo"
  var _unitIdentifier: String?

  @Relationship(deleteRule: .cascade, inverse: \QuestionOption.question)
  var _options: [QuestionOption]? = []

  /// Answers recorded against this question.
  @Relationship(deleteRule: .nullify, inverse: \Answer.question)
  public var answers: [Answer]? = []

  var _pilot: Pilot?
  var _aircraft: Aircraft?
  var _globalSettings: GlobalRiskSettings?
  var _airportApplicability: AirportApplicability?

  /// Type of question (yes/no, multiple choice, or numeric buckets) reconstructed from its options.
  public var type: QuestionType {
    let options = _options ?? []
    switch _kind {
      case "multipleChoice":
        let choices =
          options
          .sorted { $0.sortOrder < $1.sortOrder }
          .map { Choice(label: $0.label) }
        return .multipleChoice(choices)
      case "numericBuckets":
        let buckets =
          options
          .sorted { $0.sortOrder < $1.sortOrder }
          .map { option -> Bucket in
            let bounds = option.bounds
            return Bucket(label: option.label, lowerBound: bounds?.lower, upperBound: bounds?.upper)
          }
        return .numericBuckets(unit: _unitIdentifier, buckets)
      default:
        return .yesNo
    }
  }

  /// Scope this question is attached to (pilot, aircraft, global, or airport).
  public var scope: QuestionScope {
    if let pilot = _pilot {
      return .pilot(pilot)
    }
    if let aircraft = _aircraft {
      return .aircraft(aircraft)
    }
    if let global = _globalSettings {
      if let applicability = _airportApplicability {
        return .airport(global, applicability: applicability)
      }
      return .global(global)
    }
    fatalError("Question has no scope set — invariant violated")
  }

  /// Creates a question with the given content, type, and scope.
  public init(
    title: String,
    category: RiskCategory,
    type: QuestionType,
    scope: QuestionScope,
    subtitle: String? = nil,
    sortOrder: Int = 0
  ) {
    self.title = title
    self.subtitle = subtitle
    self.category = category
    self.sortOrder = sortOrder
    applyType(type)
    applyScope(scope)
  }

  /// Replaces the question type, deleting any existing options and seeding new ones.
  public func setType(_ newValue: QuestionType, in context: ModelContext) {
    for option in _options ?? [] {
      context.delete(option)
    }
    _options = []
    applyType(newValue, context: context)
  }

  /// Replaces the question scope, clearing any previous parent relationship.
  public func setScope(_ newValue: QuestionScope) {
    applyScope(newValue)
  }

  private func applyType(_ value: QuestionType, context: ModelContext? = nil) {
    switch value {
      case .yesNo:
        _kind = "yesNo"
        _unitIdentifier = nil
        if _options == nil { _options = [] }
        for (index, label) in ["Yes", "No"].enumerated() {
          let option = QuestionOption(label: label, sortOrder: index)
          option.question = self
          _options?.append(option)
          context?.insert(option)
        }
      case .multipleChoice(let choices):
        _kind = "multipleChoice"
        _unitIdentifier = nil
        if _options == nil { _options = [] }
        for (index, choice) in choices.enumerated() {
          let option = QuestionOption(label: choice.label, sortOrder: index)
          option.question = self
          _options?.append(option)
          context?.insert(option)
        }
      case let .numericBuckets(unit, buckets):
        _kind = "numericBuckets"
        _unitIdentifier = unit
        if _options == nil { _options = [] }
        for (index, bucket) in buckets.enumerated() {
          let option = QuestionOption(
            label: bucket.label,
            sortOrder: index,
            bounds: (bucket.lowerBound, bucket.upperBound)
          )
          option.question = self
          _options?.append(option)
          context?.insert(option)
        }
    }
  }

  private func applyScope(_ value: QuestionScope) {
    _pilot = nil
    _aircraft = nil
    _globalSettings = nil
    _airportApplicability = nil
    switch value {
      case .pilot(let pilot):
        _pilot = pilot
      case .aircraft(let aircraft):
        _aircraft = aircraft
      case .global(let global):
        _globalSettings = global
      case let .airport(global, applicability):
        _globalSettings = global
        _airportApplicability = applicability
    }
  }
}
