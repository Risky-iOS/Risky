import Foundation
import SwiftData

/// Singleton settings record holding the pilot’s global risk-question configuration. Exactly one
/// instance is expected to exist per CloudKit zone; ``DefaultQuestionSeeder`` enforces this.
@Model
public final class GlobalRiskSettings {
  /// Date at which this record was inserted into the store.
  public var createdAt = Date()
  /// Whether the default global question library has already been seeded for this record.
  public var didSeedDefaults = false

  /// Global and airport-scoped questions that hang off this settings record.
  @Relationship(deleteRule: .cascade, inverse: \Question._globalSettings)
  public var questions: [Question]? = []

  /// Creates a fresh settings record. Defaults remain unseeded until ``DefaultQuestionSeeder`` runs.
  public init() {}
}
