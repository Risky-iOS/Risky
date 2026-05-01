import Foundation

/// Test/preview helpers for ``NavDataLoaderViewModel`` — used only by
/// SwiftUI `#Preview` blocks, which are stripped from release builds.
enum MockNavDataLoaderViewModel {
  /// Returns a ``NavDataLoaderViewModel`` whose properties are pre-set for
  /// the given scenario. The freshness poll is suppressed so the preview
  /// stays static.
  @MainActor
  static func factory(scenario: Scenario) -> NavDataLoaderViewModel {
    let viewModel = NavDataLoaderViewModel(autostartObservation: false)

    switch scenario {
      case .noData:
        viewModel.noData = true
        viewModel.needsLoad = true
        viewModel.canSkip = false
      case .outOfDate:
        viewModel.noData = false
        viewModel.needsLoad = true
        viewModel.canSkip = true
      case .outOfDateExpensive:
        viewModel.noData = false
        viewModel.needsLoad = true
        viewModel.canSkip = true
        viewModel.networkIsExpensive = true
      case .downloading:
        viewModel.noData = true
        viewModel.needsLoad = true
        viewModel.canSkip = false
        viewModel.state = .downloading(progress: 0.38)
      case .decompressing:
        viewModel.noData = true
        viewModel.needsLoad = true
        viewModel.canSkip = false
        viewModel.state = .extracting(progress: nil)
    }

    return viewModel
  }

  enum Scenario {
    /// First launch — no payload cached, no defer button.
    case noData
    /// Cached payload exists but its NASR cycle has expired; defer is allowed.
    case outOfDate
    /// As ``outOfDate``, but the user is on a metered network.
    case outOfDateExpensive
    /// Mid-download, ~38 % complete.
    case downloading
    /// Decompressing the LZMA payload.
    case decompressing
  }
}
