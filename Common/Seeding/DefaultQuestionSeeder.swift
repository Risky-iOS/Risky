import Foundation
import SwiftData

/// Seeds the SwiftData store with the default global, pilot, and aircraft questions when a profile
/// is first created. Idempotent: running it again on a populated store is a no-op.
@MainActor
public struct DefaultQuestionSeeder {
  private let templates: [QuestionTemplate]

  /// Creates a seeder loading templates from the framework bundle.
  public init() throws {
    self.templates = try QuestionTemplateLibrary.loadBundled()
  }

  /// Creates a seeder with an explicit set of templates. Used by tests.
  public init(templates: [QuestionTemplate]) {
    self.templates = templates
  }

  /// Ensures a single ``GlobalRiskSettings`` exists and seeds the default global questions if they
  /// have not already been seeded.
  public func seedGlobalIfNeeded(context: ModelContext) throws {
    let descriptor = FetchDescriptor<GlobalRiskSettings>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]
    )
    var existing = try context.fetch(descriptor)
    let survivor: GlobalRiskSettings
    if let first = existing.first {
      survivor = first
      existing.removeFirst()
      for duplicate in existing {
        for question in duplicate.questions ?? [] {
          question._globalSettings = survivor
        }
        context.delete(duplicate)
      }
    } else {
      survivor = GlobalRiskSettings()
      context.insert(survivor)
    }

    guard !survivor.didSeedDefaults else { return }

    let globalTemplates = templates.filter {
      $0.category == .environment || $0.category == .externalPressures
    }
    for (index, template) in globalTemplates.enumerated() {
      let scope: QuestionScope
      if let applicability = template.airportApplicability {
        scope = .airport(survivor, applicability: applicability)
      } else {
        scope = .global(survivor)
      }
      let question = Question(
        title: template.title,
        category: template.category,
        type: template.type,
        scope: scope,
        subtitle: template.subtitle,
        sortOrder: index
      )
      context.insert(question)
    }
    survivor.didSeedDefaults = true
  }

  /// Seeds pilot-scoped questions for a freshly created pilot.
  public func populatePilot(_ pilot: Pilot, context: ModelContext) {
    let pilotTemplates = templates.filter { $0.category == .pilot }
    for (index, template) in pilotTemplates.enumerated() {
      let question = Question(
        title: template.title,
        category: .pilot,
        type: template.type,
        scope: .pilot(pilot),
        subtitle: template.subtitle,
        sortOrder: index
      )
      context.insert(question)
    }
  }

  /// Seeds aircraft-scoped questions for a freshly created aircraft.
  public func populateAircraft(_ aircraft: Aircraft, context: ModelContext) {
    let aircraftTemplates = templates.filter { $0.category == .aircraft }
    for (index, template) in aircraftTemplates.enumerated() {
      let question = Question(
        title: template.title,
        category: .aircraft,
        type: template.type,
        scope: .aircraft(aircraft),
        subtitle: template.subtitle,
        sortOrder: index
      )
      context.insert(question)
    }
  }
}
