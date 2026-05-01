import Foundation

public enum AnswerValue: Hashable {
  /// yesNo or multipleChoice — the chosen option carries the stoplight.
  case choice(QuestionOption)
  /// numericBuckets — the raw measured value plus the bucket it fell into.
  case bucket(value: Double, bucket: QuestionOption)
}
