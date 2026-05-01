import SwiftNASR
import SwiftUI

struct ContentView: View {
  @SwiftUI.State private var viewModel = ProcessorViewModel()

  private var uploadErrorBinding: Binding<Bool> {
    Binding(
      get: { viewModel.uploadError != nil },
      set: { _ in }
    )
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Risky Data Processor")
        .font(.title)
        .fontWeight(.bold)
        .padding(.bottom)

      if !viewModel.missingCredentials.isEmpty {
        Label(
          "Missing credentials: \(viewModel.missingCredentials.joined(separator: ", "))",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
        .padding(.bottom)
      }

      ControlsForm(viewModel: viewModel)

      if viewModel.showProgressBar {
        ProgressView(value: viewModel.progress) {
          Text(viewModel.statusMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .progressViewStyle(.linear)
      }

      LogViewer(entries: viewModel.logEntries)

      if let errorMessage = viewModel.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .padding()
          .foregroundStyle(.red)
      }
    }
    .padding(30)
    .frame(minWidth: 720, minHeight: 540)
    .alert(
      "Upload Error",
      isPresented: uploadErrorBinding,
      presenting: viewModel.uploadError
    ) { _ in
      Button("OK") { viewModel.uploadError = nil }
    } message: { error in
      VStack(alignment: .leading) {
        Text(error.localizedDescription)
        if let failureReason = error.localizedFailureReason {
          Text(failureReason).font(.caption)
        }
        if let recoverySuggestion = error.localizedRecoverySuggestion {
          Text(recoverySuggestion).font(.caption)
        }
      }
    }
  }
}

private struct ControlsForm: View {
  @Bindable var viewModel: ProcessorViewModel

  var body: some View {
    HStack {
      Form {
        HStack {
          Picker("Cycle", selection: $viewModel.cycleSelection) {
            Text("Current").tag(ProcessorViewModel.CycleSelection.current)
            Text("Next").tag(ProcessorViewModel.CycleSelection.next)
          }
          .pickerStyle(.segmented)
          .disabled(viewModel.isProcessing)

          if let cycle = viewModel.resolvedCycle,
            let start = cycle.effectiveDate,
            let end = cycle.expirationDate
          {
            CycleDateRange(start: start, end: end)
          }
        }

        Toggle("Skip upload", isOn: $viewModel.skipUpload)
          .disabled(viewModel.isProcessing)
      }

      Spacer()

      if viewModel.isProcessing {
        Button(viewModel.isCancelling ? "Stopping…" : "Stop") {
          viewModel.cancel()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
        .disabled(viewModel.isCancelling)
      } else {
        Button("Run") {
          viewModel.refreshCredentialStatus()
          viewModel.runPipeline()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!viewModel.missingCredentials.isEmpty)
      }
    }
  }
}

private struct CycleDateRange: View {
  let start: Date
  let end: Date

  var body: some View {
    Text(start..<end, format: .interval.year().month().day())
      .foregroundStyle(.secondary)
      .font(.caption)
  }
}

#Preview("Idle") {
  ContentView()
}
