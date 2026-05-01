import Foundation

public enum AirportApplicability: String, Codable, CaseIterable, Sendable {
  case departure
  case destination
  case both
}
