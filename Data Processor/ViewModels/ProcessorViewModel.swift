import Foundation
import Logging
import Observation
import SwiftNASR

/// View-state for the Data Processor's SwiftUI surface.
@MainActor
@Observable
final class ProcessorViewModel {
  var cycleSelection: CycleSelection = .current
  var skipUpload: Bool = false

  var isProcessing: Bool = false
  var isCancelling: Bool = false
  var progress: Double = 0
  var statusMessage: String = ""

  /// Inline error from the local pipeline (cycle resolution, processor failure).
  var errorMessage: String?

  /// Upload-specific error, surfaced in a modal alert with full
  /// failure-reason / recovery-suggestion detail.
  var uploadError: NSError?

  var logEntries: [LogEntry] = []

  /// Missing-credentials list, refreshed on demand. Empty when everything
  /// is configured.
  var missingCredentials: [String] = []

  private var currentTask: Task<Void, Never>?

  /// Whether the inline progress bar should be visible.
  ///
  /// We hide it while idle or after an error, where it would be redundant
  /// or misleading.
  var showProgressBar: Bool {
    (isProcessing || !statusMessage.isEmpty) && errorMessage == nil
  }

  /// The cycle currently selected in the picker, if it can be resolved.
  var resolvedCycle: SwiftNASR.Cycle? {
    try? cycleSelection.resolve()
  }

  init() {
    Self.bootstrapLoggingIfNeeded()
    startObservingLog()
    refreshCredentialStatus()
  }

  private static func applicationSupportDirectory() -> URL {
    let fm = FileManager.default
    let support =
      (try? fm.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? fm.temporaryDirectory
    let dir = support.appending(path: "Risky Data Processor")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private static func bootstrapLoggingIfNeeded() {
    LoggingBootstrap.runOnce(level: .info)
  }

  private static func label(for stage: NavDataProcessor.Stage) -> String {
    switch stage {
      case .starting: String(localized: "Starting…")
      case .nasr: String(localized: "Downloading & parsing FAA NASR")
      case .ourAirports: String(localized: "Loading OurAirports")
      case .cifp: String(localized: "Downloading & parsing CIFP")
      case .merge: String(localized: "Merging sources")
      case .terrain: String(localized: "Sampling terrain")
      case .writing: String(localized: "Writing & compressing plist")
      case .uploading: String(localized: "Uploading to GitHub")
      case .completed: String(localized: "Completed")
    }
  }

  private static func completionMessage(
    for output: NavDataProcessor.Output,
    uploaded: Bool
  ) -> String {
    if uploaded {
      return String(
        localized:
          "Cycle “\(output.cycleName)” uploaded — \(output.airportCount, format: .number) airports."
      )
    }
    return String(
      localized:
        "Cycle “\(output.cycleName)” saved locally — \(output.airportCount, format: .number) airports."
    )
  }

  func runPipeline() {
    currentTask?.cancel()
    currentTask = Task { [weak self] in
      await self?.performRun()
    }
  }

  func cancel() {
    guard isProcessing else { return }
    isCancelling = true
    currentTask?.cancel()
  }

  func refreshCredentialStatus() {
    missingCredentials = CredentialsConfig.validateRequired()
  }

  private func performRun() async {
    isProcessing = true
    isCancelling = false
    progress = 0
    statusMessage = String(localized: "Starting…")
    errorMessage = nil
    uploadError = nil

    let logger = Logger(label: "DataProcessor.run")
    let processor = NavDataProcessor(logger: logger)

    let cycle: SwiftNASR.Cycle
    do {
      cycle = try cycleSelection.resolve()
    } catch {
      finish(withError: error)
      return
    }

    let outputDirectory = Self.applicationSupportDirectory()

    let terrainCatalog: R2TerrainCatalog?
    if let downloader = try? R2Downloader(logger: logger) {
      let manifestPath =
        CredentialsConfig[.terrainManifestPath]
        ?? CredentialsConfig.defaultTerrainManifestPath
      terrainCatalog = R2TerrainCatalog(
        downloader: downloader,
        manifestPath: manifestPath,
        cacheDirectory: outputDirectory,
        logger: logger
      )
    } else {
      terrainCatalog = nil
    }

    do {
      let output = try await processor.run(
        cycle: cycle,
        outputDirectory: outputDirectory,
        terrainCatalog: terrainCatalog,
        onProgress: { [weak self] stage, completed, total in
          await self?.handleProgress(
            stage: stage,
            completed: completed,
            total: total
          )
        }
      )

      let uploaded = await uploadIfNeeded(output: output, logger: logger)

      progress = 1
      statusMessage = Self.completionMessage(for: output, uploaded: uploaded)
      isProcessing = false

      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled, !isProcessing { reset() }
    } catch is CancellationError {
      reset()
    } catch {
      finish(withError: error)
    }
  }

  private func uploadIfNeeded(
    output: NavDataProcessor.Output,
    logger: Logger
  ) async -> Bool {
    guard !skipUpload else { return false }
    statusMessage = String(localized: "Uploading to GitHub")
    do {
      let uploader = try GitHubUploader(logger: logger)
      try await uploader.validateToken()
      try await uploader.uploadFile(
        at: output.file,
        toPath: "risky-data/\(output.cycleName).plist.lzma",
        commitMessage: "Update airport data for cycle \(output.cycleName)"
      )
      try await uploadAviationDataManifest(for: output, uploader: uploader)
      return true
    } catch {
      uploadError = error as NSError
      return false
    }
  }

  private func handleProgress(
    stage: NavDataProcessor.Stage,
    completed: Int,
    total: Int
  ) {
    progress = total > 0 ? Double(completed) / Double(total) : 0
    statusMessage = Self.label(for: stage)
  }

  private func finish(withError error: any Swift.Error) {
    errorMessage = error.localizedDescription
    statusMessage = ""
    progress = 0
    isProcessing = false
    isCancelling = false
  }

  private func reset() {
    isProcessing = false
    isCancelling = false
    progress = 0
    statusMessage = ""
    errorMessage = nil
  }

  private func startObservingLog() {
    Task { [weak self] in
      await LogCollector.shared.observe { [weak self] entries in
        Task { @MainActor in
          self?.logEntries = entries
        }
      }
    }
  }

  enum CycleSelection: Equatable, Hashable, Sendable {
    case current
    case next
    case explicit(year: UInt, month: UInt8, day: UInt8)

    func resolve() throws -> SwiftNASR.Cycle {
      switch self {
        case .current:
          return SwiftNASR.Cycle.effective
        case .next:
          guard let next = SwiftNASR.Cycle.effective.next else {
            throw NSError(
              domain: "Cycle",
              code: 2,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Couldn’t determine the next NASR cycle."
              ]
            )
          }
          return next
        case let .explicit(year, month, day):
          return SwiftNASR.Cycle(year: year, month: month, day: day)
      }
    }
  }
}
