import RiskyCommon
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var loader: NavDataLoaderViewModel?

  var body: some View {
    Group {
      if let loader {
        if loader.showLoader {
          LoadingView()
            .environment(loader)
        } else {
          HomePageView()
        }
      } else {
        ProgressView()
      }
    }
    .onAppear {
      if loader == nil { loader = NavDataLoaderViewModel() }
    }
  }
}

private struct HomePageView: View {
  var body: some View {
    Text("Risky")
      .font(.largeTitle)
      .padding()
  }
}

#Preview("Home page") {
  HomePageView()
}

#Preview("Loader, no data") {
  LoadingView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .noData))
}
