import Foundation

// swiftlint:disable redundant_string_enum_value
public enum RiskCategory: String, Codable, CaseIterable, Sendable {
  case pilot = "pilot"
  case aircraft = "aircraft"
  case environment = "environment"
  case externalPressures = "externalPressures"
}
// swiftlint:enable redundant_string_enum_value
