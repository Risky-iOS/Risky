import Foundation

/// The shape of a risk question’s answer space.
public enum QuestionType: Sendable, Hashable {
  /// A simple yes/no question.
  case yesNo
  /// A pick-one question whose choices are pre-enumerated.
  case multipleChoice([Choice])
  /// A numeric value bucketed into named ranges, with an optional measurement unit identifier.
  case numericBuckets(unit: String?, [Bucket])
}

/// One labeled option in a multiple-choice question.
public struct Choice: Codable, Sendable, Hashable {
  /// User-facing label for the choice.
  public let label: String

  /// Creates a choice with the given label.
  public init(label: String) {
    self.label = label
  }
}

/// One labeled bucket in a numeric-bucket question.
public struct Bucket: Codable, Sendable, Hashable {
  /// User-facing label for the bucket.
  public let label: String
  /// Inclusive lower bound; `nil` means open-ended on the low side.
  public let lowerBound: Double?
  /// Exclusive upper bound; `nil` means open-ended on the high side.
  public let upperBound: Double?

  /// Creates a bucket with the given label and bounds.
  public init(label: String, lowerBound: Double?, upperBound: Double?) {
    self.label = label
    self.lowerBound = lowerBound
    self.upperBound = upperBound
  }
}

extension QuestionType: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    switch kind {
      case .yesNo:
        self = .yesNo
      case .multipleChoice:
        let choices = try container.decode([Choice].self, forKey: .choices)
        self = .multipleChoice(choices)
      case .numericBuckets:
        let unit = try container.decodeIfPresent(String.self, forKey: .unit)
        let buckets = try container.decode([Bucket].self, forKey: .buckets)
        self = .numericBuckets(unit: unit, buckets)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .yesNo:
        try container.encode(Kind.yesNo, forKey: .kind)
      case .multipleChoice(let choices):
        try container.encode(Kind.multipleChoice, forKey: .kind)
        try container.encode(choices, forKey: .choices)
      case let .numericBuckets(unit, buckets):
        try container.encode(Kind.numericBuckets, forKey: .kind)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encode(buckets, forKey: .buckets)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case unit
    case choices
    case buckets
  }

  // swiftlint:disable redundant_string_enum_value
  private enum Kind: String, Codable {
    case yesNo = "yesNo"
    case multipleChoice = "multipleChoice"
    case numericBuckets = "numericBuckets"
  }
  // swiftlint:enable redundant_string_enum_value
}
