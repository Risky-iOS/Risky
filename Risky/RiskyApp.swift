import SwiftUI
import SwiftData
import RiskyCommon

@main
struct RiskyApp: App {
  let sharedModelContainer: ModelContainer

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          do {
            let seeder = try DefaultQuestionSeeder()
            try seeder.seedGlobalIfNeeded(context: sharedModelContainer.mainContext)
          } catch {
            assertionFailure("Default-question seeding failed: \(error)")
          }
        }
    }
    .modelContainer(sharedModelContainer)
  }

  init() {
    do {
      self.sharedModelContainer = try ModelContainer.risky()
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }
}
