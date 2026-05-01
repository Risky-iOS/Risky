import Foundation

public enum ApproachType: String, Codable, CaseIterable, Sendable {
  case ILS
  case LOC
  case RNAV
  case VOR
  case NDB
  case GPS
  case LDA
}
