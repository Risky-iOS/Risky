import Foundation

/// Fixture builders for SwiftUI `#Preview` blocks in the Data Processor.
@MainActor
enum PreviewHelper {
  static let sampleLogEntries: [LogEntry] = {
    let now = Date()
    return [
      LogEntry(
        timestamp: now.addingTimeInterval(-30),
        severity: .notice,
        message: "Downloading FAA NASR for cycle 2026-05-01…"
      ),
      LogEntry(
        timestamp: now.addingTimeInterval(-25),
        severity: .info,
        message: "NASR archive 412 MB."
      ),
      LogEntry(
        timestamp: now.addingTimeInterval(-20),
        severity: .debug,
        message: "Parsed 20,123 airport records."
      ),
      LogEntry(
        timestamp: now.addingTimeInterval(-15),
        severity: .warning,
        message: "Retrying “OurAirports airports.csv” (attempt 2/4) after 1.1s: timed out."
      ),
      LogEntry(
        timestamp: now.addingTimeInterval(-10),
        severity: .notice,
        message: "Downloading CIFP zip…"
      ),
      LogEntry(
        timestamp: now.addingTimeInterval(-2),
        severity: .error,
        message: "Upload failed: invalid GitHub token."
      )
    ]
  }()

  static func viewModel(
    isProcessing: Bool = false,
    isCancelling: Bool = false,
    progress: Double = 0,
    statusMessage: String = "",
    errorMessage: String? = nil,
    uploadError: NSError? = nil,
    logEntries: [LogEntry] = [],
    missingCredentials: [String] = [],
    cycle: ProcessorViewModel.CycleSelection = .current,
    skipUpload: Bool = false
  ) -> ProcessorViewModel {
    let viewModel = ProcessorViewModel()
    viewModel.isProcessing = isProcessing
    viewModel.isCancelling = isCancelling
    viewModel.progress = progress
    viewModel.statusMessage = statusMessage
    viewModel.errorMessage = errorMessage
    viewModel.uploadError = uploadError
    viewModel.logEntries = logEntries
    viewModel.missingCredentials = missingCredentials
    viewModel.cycleSelection = cycle
    viewModel.skipUpload = skipUpload
    return viewModel
  }

  struct PreviewError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
}
