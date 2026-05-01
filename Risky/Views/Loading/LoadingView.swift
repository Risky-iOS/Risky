import SwiftUI

/// Routes between the consent and progress screens based on the loader's
/// current state.
struct LoadingView: View {
  @Environment(NavDataLoaderViewModel.self)
  private var loader

  var body: some View {
    @Bindable var loader = loader
    content
      .withErrorSheet(error: $loader.error)
  }

  @ViewBuilder private var content: some View {
    switch loader.state {
      case .idle:
        LoadingConsentView()
      default:
        LoadingProgressView()
    }
  }
}

#Preview("Idle, no data") {
  LoadingView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .noData))
}

#Preview("Downloading") {
  LoadingView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .downloading))
}
