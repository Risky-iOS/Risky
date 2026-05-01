import Foundation
import Logging
import SwiftNASR

/// Runs the Data Processor pipeline non-interactively, driven by environment
/// variables. Used by CI and from the command line.
///
/// Recognized environment variables:
/// - `RISKY_HEADLESS=1` — required (gate flag, checked by ``DataProcessorApp``).
/// - `RISKY_NASR_CYCLE` — `current` (default), `next`, or `YYYY-MM-DD`.
/// - `RISKY_SKIP_UPLOAD=1` — write `{cycle}.plist.lzma` locally but skip
///   the GitHub upload.
struct HeadlessProcessor {
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

  /// Returns a process exit code: 0 success, 1 failure.
  func run(environment: [String: String]) async -> Int32 {
    let logger = Logger(label: "DataProcessor.headless")
    logger.notice("Starting Risky Data Processor in headless mode")

    let cycle: SwiftNASR.Cycle
    do {
      cycle = try resolveCycle(from: environment["RISKY_NASR_CYCLE"])
    } catch {
      logger.error("Cycle resolution failed: \(error.localizedDescription)")
      return 1
    }
    logger.notice("Targeting NASR cycle \(cycle.description)")

    let skipUpload = environment["RISKY_SKIP_UPLOAD"] == "1"
    if skipUpload {
      logger.notice("RISKY_SKIP_UPLOAD=1 — output will not be uploaded to GitHub")
    }

    let outputDirectory = Self.applicationSupportDirectory()
    let processor = NavDataProcessor(logger: logger)

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
      logger.warning(
        "Terrain credentials missing — every airport will get mountainousTerrain=false"
      )
      terrainCatalog = nil
    }

    let output: NavDataProcessor.Output
    do {
      let progressTracker = HeadlessProgressTracker(logger: logger)
      output = try await processor.run(
        cycle: cycle,
        outputDirectory: outputDirectory,
        terrainCatalog: terrainCatalog,
        onProgress: { stage, completed, total in
          await progressTracker.report(stage: stage, completed: completed, total: total)
        }
      )
    } catch {
      logger.error("Pipeline failed: \(error.localizedDescription)")
      return 1
    }

    logger.notice(
      "Wrote \(output.file.path) (\(output.compressedBytes) bytes, \(output.airportCount) airports)"
    )

    if !skipUpload {
      do {
        let uploader = try GitHubUploader(logger: logger)
        try await uploader.validateToken()
        try await uploader.uploadFile(
          at: output.file,
          toPath: "risky-data/\(output.cycleName).plist.lzma",
          commitMessage: "Update airport data for cycle \(output.cycleName)"
        )
        try await uploadAviationDataManifest(for: output, uploader: uploader)
        logger.notice("Upload complete")
      } catch {
        logger.error("Upload failed: \(error.localizedDescription)")
        return 1
      }
    }

    return 0
  }

  private func resolveCycle(from raw: String?) throws -> SwiftNASR.Cycle {
    let value = (raw ?? "current").trimmingCharacters(in: .whitespacesAndNewlines)
    switch value.lowercased() {
      case "", "current":
        return SwiftNASR.Cycle.effective
      case "next":
        guard let next = SwiftNASR.Cycle.effective.next else {
          throw NSError(
            domain: "Headless",
            code: 2,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Couldn’t determine the next cycle."
            ]
          )
        }
        return next
      default:
        if let cycle = SwiftNASR.Cycle(value) {
          return cycle
        }
        throw NSError(
          domain: "Headless",
          code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              "RISKY_NASR_CYCLE “\(value)” is not “current”, “next”, or YYYY-MM-DD."
          ]
        )
    }
  }
}

/// Coalesces frequent progress updates so headless logs stay readable.
/// Only logs when either the stage changes or the completed-percent has
/// advanced by `step` since the last emission.
private actor HeadlessProgressTracker {
  private let logger: Logger
  private let step: Int = 10
  private var lastStage: String?
  private var lastEmittedPercent: Int = -1

  init(logger: Logger) {
    self.logger = logger
  }

  func report(stage: NavDataProcessor.Stage, completed: Int, total: Int) {
    let stageName = String(describing: stage)
    if stageName != lastStage {
      logger.notice("Stage \(stageName): \(completed)%")
      lastStage = stageName
      lastEmittedPercent = completed
      return
    }
    if completed - lastEmittedPercent >= step || completed == total {
      logger.notice("Stage \(stageName): \(completed)%")
      lastEmittedPercent = completed
    }
  }
}
