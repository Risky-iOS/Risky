import SwiftUI

/// Two-stage progress UI shown after the pilot taps **Download**.
///
/// Stage 1 covers fetching the manifest + payload bytes from GitHub
/// (`NavDataLoader.State.downloading`); stage 2 covers LZMA decompression
/// + atomic on-disk write (`.extracting`).
struct LoadingProgressView: View {
  @Environment(NavDataLoaderViewModel.self)
  private var loader

  private var downloadProgress: StepProgress {
    switch loader.state {
      case .idle: return .pending
      case .downloading(let progress):
        if let progress { return .inProgress(progress: progress) }
        return .indeterminate
      case .extracting, .finished: return .complete
    }
  }

  private var decompressProgress: StepProgress {
    switch loader.state {
      case .idle, .downloading: return .pending
      case .extracting(let progress):
        if let progress { return .inProgress(progress: progress) }
        return .indeterminate
      case .finished: return .complete
    }
  }

  var body: some View {
    VStack {
      Image(systemName: "airplane.departure")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: 96, alignment: .center)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      Text("Loading latest airport information…")
        .padding(.bottom, 20)

      Grid(alignment: .leading) {
        GridRow {
          CircularProgressView(progress: downloadProgress)
          Text(downloadProgress == .complete ? "Downloaded" : "Downloading…")
            .foregroundStyle(downloadProgress == .pending ? .secondary : .primary)
        }

        GridRow {
          CircularProgressView(progress: decompressProgress)
          Text(decompressProgress == .complete ? "Decompressed" : "Decompressing…")
            .foregroundStyle(decompressProgress == .pending ? .secondary : .primary)
        }
      }
    }
  }
}

#Preview("Downloading") {
  LoadingProgressView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .downloading))
}

#Preview("Decompressing") {
  LoadingProgressView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .decompressing))
}
