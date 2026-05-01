import Foundation
import SwiftData
import Testing
@testable import RiskyCommon

@MainActor
struct DefaultQuestionSeederTests {
  private func makeContext() throws -> ModelContext {
    let container = try ModelContainer.risky(inMemory: true)
    return ModelContext(container)
  }

  @Test
  func seedGlobalIsIdempotent() throws {
    let context = try makeContext()
    let seeder = try DefaultQuestionSeeder()

    try seeder.seedGlobalIfNeeded(context: context)
    try seeder.seedGlobalIfNeeded(context: context)

    let globals = try context.fetch(FetchDescriptor<GlobalRiskSettings>())
    #expect(globals.count == 1)
    let survivor = try #require(globals.first)
    #expect(survivor.didSeedDefaults)

    let templates = try QuestionTemplateLibrary.loadBundled()
    let expectedCount = templates.filter {
      $0.category == .environment || $0.category == .externalPressures
    }.count
    let questions = survivor.questions ?? []
    #expect(questions.count == expectedCount)

    for question in questions {
      for option in question._options ?? [] {
        #expect(option.stoplight == nil)
      }
    }
  }

  @Test
  func yesNoQuestionsHaveYesAndNoOptions() throws {
    let context = try makeContext()
    let seeder = try DefaultQuestionSeeder()
    try seeder.seedGlobalIfNeeded(context: context)

    let survivor = try #require(try context.fetch(FetchDescriptor<GlobalRiskSettings>()).first)
    let yesNoQuestions = (survivor.questions ?? []).filter { $0.type == .yesNo }
    #expect(!yesNoQuestions.isEmpty)
    for question in yesNoQuestions {
      let labels = (question._options ?? [])
        .sorted { $0.sortOrder < $1.sortOrder }
        .map(\.label)
      #expect(labels == ["Yes", "No"])
    }
  }

  @Test
  func airportTemplatesProduceAirportScope() throws {
    let context = try makeContext()
    let seeder = try DefaultQuestionSeeder()
    try seeder.seedGlobalIfNeeded(context: context)

    let survivor = try #require(try context.fetch(FetchDescriptor<GlobalRiskSettings>()).first)
    let airportQuestions = (survivor.questions ?? []).filter { question in
      if case .airport = question.scope { return true }
      return false
    }
    #expect(!airportQuestions.isEmpty)
    for question in airportQuestions {
      switch question.scope {
        case .airport(_, let applicability):
          #expect(AirportApplicability.allCases.contains(applicability))
        default:
          Issue.record("Expected .airport scope")
      }
    }
  }

  @Test
  func collapsesDuplicateGlobalsAndMergesQuestions() throws {
    let context = try makeContext()
    let older = GlobalRiskSettings()
    older.createdAt = Date(timeIntervalSince1970: 0)
    older.didSeedDefaults = true
    context.insert(older)

    let seededQuestion = Question(
      title: "External: legacy",
      category: .externalPressures,
      type: .yesNo,
      scope: .global(older)
    )
    context.insert(seededQuestion)

    let newer = GlobalRiskSettings()
    newer.createdAt = Date(timeIntervalSince1970: 1000)
    context.insert(newer)
    let newerQuestion = Question(
      title: "External: from newer",
      category: .externalPressures,
      type: .yesNo,
      scope: .global(newer)
    )
    context.insert(newerQuestion)

    let seeder = try DefaultQuestionSeeder()
    try seeder.seedGlobalIfNeeded(context: context)

    let globals = try context.fetch(FetchDescriptor<GlobalRiskSettings>())
    #expect(globals.count == 1)
    let survivor = try #require(globals.first)
    #expect(survivor.createdAt == Date(timeIntervalSince1970: 0))
    let titles = Set((survivor.questions ?? []).map(\.title))
    #expect(titles.contains("External: legacy"))
    #expect(titles.contains("External: from newer"))
  }

  @Test
  func populatePilotProducesPilotQuestions() throws {
    let context = try makeContext()
    let pilot = Pilot(name: "Test")
    context.insert(pilot)

    let seeder = try DefaultQuestionSeeder()
    seeder.populatePilot(pilot, context: context)

    let templates = try QuestionTemplateLibrary.loadBundled()
    let expectedPilot = templates.filter { $0.category == .pilot }.count
    #expect((pilot.questions ?? []).count == expectedPilot)

    for question in pilot.questions ?? [] {
      switch question.scope {
        case .pilot(let owner):
          #expect(owner === pilot)
        default:
          Issue.record("Expected .pilot scope")
      }
    }
  }
}
