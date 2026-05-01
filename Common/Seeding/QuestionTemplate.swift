import Foundation

public struct QuestionTemplateFile: Decodable, Sendable {
  public let questions: [QuestionTemplate]
}

public struct QuestionTemplate: Decodable, Sendable {
  public let category: RiskCategory
  public let title: String
  public let subtitle: String?
  public let type: QuestionType
  public let airportApplicability: AirportApplicability?
}
