import Foundation

enum StepProgress: Equatable {
  case pending
  case inProgress(progress: Float)
  case indeterminate
  case complete

  var isLoading: Bool {
    switch self {
      case .pending: return false
      case .inProgress: return true
      case .indeterminate: return true
      case .complete: return false
    }
  }
}
