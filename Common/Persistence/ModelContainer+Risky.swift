import Foundation
import SwiftData

public extension ModelContainer {
  /// Creates the SwiftData container Risky uses for its persistent store, including the schema and
  /// CloudKit configuration. Pass ``inMemory`` for tests and previews to skip persistence.
  static func risky(inMemory: Bool = false) throws -> ModelContainer {
    let schema = Schema([
      Pilot.self,
      Aircraft.self,
      GlobalRiskSettings.self,
      Question.self,
      QuestionOption.self,
      Squawk.self,
      Flight.self,
      Answer.self,
      Airport.self,
      Runway.self,
      Approach.self
    ])
    let configuration: ModelConfiguration
    if inMemory {
      configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    } else {
      configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier(appGroupIdentifier),
        cloudKitDatabase: .private("iCloud.codes.tim.Risky")
      )
    }
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}
