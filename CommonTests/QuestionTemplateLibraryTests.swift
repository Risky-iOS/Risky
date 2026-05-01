import Foundation
import Testing
@testable import RiskyCommon

struct QuestionTemplateLibraryTests {
  @Test
  func loadBundledReturnsExpectedCount() throws {
    let templates = try QuestionTemplateLibrary.loadBundled()
    #expect(templates.count == 13)
  }

  @Test
  func categoryCounts() throws {
    let templates = try QuestionTemplateLibrary.loadBundled()
    #expect(templates.filter { $0.category == .pilot }.count == 7)
    #expect(templates.filter { $0.category == .aircraft }.count == 2)
    #expect(templates.filter { $0.category == .environment }.count == 1)
    #expect(templates.filter { $0.category == .externalPressures }.count == 3)
  }

  @Test
  func numericBucketsAreContiguous() throws {
    let templates = try QuestionTemplateLibrary.loadBundled()
    for template in templates {
      guard case .numericBuckets(_, let buckets) = template.type else { continue }
      #expect(buckets.first?.lowerBound == nil || buckets.first?.lowerBound == 0)
      #expect(buckets.last?.upperBound == nil)
      let lowers = buckets.compactMap(\.lowerBound)
      #expect(lowers == lowers.sorted())
    }
  }

  @Test
  func airportApplicabilityOnlyOnEnvironment() throws {
    let templates = try QuestionTemplateLibrary.loadBundled()
    for template in templates where template.airportApplicability != nil {
      #expect(template.category == .environment)
    }
  }

  @Test
  func categoryTitlePairsAreUnique() throws {
    let templates = try QuestionTemplateLibrary.loadBundled()
    var seen: Set<String> = []
    for template in templates {
      let key = "\(template.category.rawValue)|\(template.title)"
      #expect(!seen.contains(key), "Duplicate (category, title): \(key)")
      seen.insert(key)
    }
  }
}
