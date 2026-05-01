import Foundation
import Logging
import SwiftUI
import SwiftNASR

/// Top-level entry point for the Data Processor target.
///
/// When the `RISKY_HEADLESS=1` environment variable is set, control is
/// handed to ``HeadlessProcessor`` and the SwiftUI window is suppressed.
/// Otherwise the SwiftUI GUI in ``ContentView`` runs as normal.
@main
struct DataProcessorApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }

  init() {
    LoggingBootstrap.runOnce(level: .info)
    Self.checkForHeadlessMode()
  }

  private static func checkForHeadlessMode() {
    let env = ProcessInfo.processInfo.environment
    guard env["RISKY_HEADLESS"] == "1" else { return }

    // Run the headless pipeline on a detached task and exit when done.
    // We're inside `App.init` here, so a Task is the right place to do
    // this — the SwiftUI lifecycle will spin up but our exit beats it.
    Task.detached(priority: .userInitiated) {
      let exitCode = await HeadlessProcessor().run(environment: env)
      exit(exitCode)
    }
  }
}
