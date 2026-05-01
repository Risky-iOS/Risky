import Foundation
import Testing
@testable import RiskyCommon

struct QuestionTypeCodableTests {
  private func roundTrip(_ value: QuestionType) throws -> QuestionType {
    let data = try PropertyListEncoder().encode(["type": value])
    let decoded = try PropertyListDecoder().decode([String: QuestionType].self, from: data)
    return try #require(decoded["type"])
  }

  @Test
  func yesNoRoundTrips() throws {
    let result = try roundTrip(.yesNo)
    #expect(result == .yesNo)
  }

  @Test
  func multipleChoiceRoundTrips() throws {
    let original: QuestionType = .multipleChoice([
      Choice(label: "Low"),
      Choice(label: "Medium"),
      Choice(label: "High")
    ])
    #expect(try roundTrip(original) == original)
  }

  @Test
  func numericBucketsRoundTrip() throws {
    let original: QuestionType = .numericBuckets(
      unit: "days",
      [
        Bucket(label: "<7", lowerBound: nil, upperBound: 7),
        Bucket(label: "7–30", lowerBound: 7, upperBound: 30),
        Bucket(label: "≥30", lowerBound: 30, upperBound: nil)
      ]
    )
    #expect(try roundTrip(original) == original)
  }

  @Test
  func numericBucketsWithoutUnitRoundTrip() throws {
    let original: QuestionType = .numericBuckets(
      unit: nil,
      [
        Bucket(label: "few", lowerBound: nil, upperBound: 1),
        Bucket(label: "many", lowerBound: 1, upperBound: nil)
      ]
    )
    #expect(try roundTrip(original) == original)
  }
}
