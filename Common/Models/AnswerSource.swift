import Foundation

public enum AnswerSource: String, Codable, CaseIterable, Sendable {
  case auto
  case manual
  case override
}
