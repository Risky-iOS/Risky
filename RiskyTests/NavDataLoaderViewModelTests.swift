import Foundation
import RiskyCommon
import Testing

@testable import Risky

@Suite("NavDataLoaderViewModel snapshot table")
struct NavDataLoaderViewModelSnapshotTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private static let future = now.addingTimeInterval(60 * 60 * 24 * 14)
  private static let past = now.addingTimeInterval(-60 * 60 * 24)

  @Test("Empty cache forces a non-skippable download")
  func emptyCache() {
    let snapshot = NavDataLoaderViewModel.snapshot(from: nil, now: Self.now)
    #expect(snapshot == .init(noData: true, needsLoad: true, canSkip: false))
  }

  @Test("Cached + current schema + not expired hides the loader")
  func currentAndFresh() {
    let local = makeLocal(expires: Self.future)
    let snapshot = NavDataLoaderViewModel.snapshot(from: local, now: Self.now)
    #expect(snapshot == .init(noData: false, needsLoad: false, canSkip: true))
  }

  @Test("Cached but expired allows defer")
  func cachedButExpired() {
    let local = makeLocal(expires: Self.past)
    let snapshot = NavDataLoaderViewModel.snapshot(from: local, now: Self.now)
    #expect(snapshot == .init(noData: false, needsLoad: true, canSkip: true))
  }

  @Test("Schema bump forces a non-skippable refresh even with cached data")
  func schemaOutOfDate() {
    let local = makeLocal(expires: Self.future, schemaVersion: -1)
    let snapshot = NavDataLoaderViewModel.snapshot(from: local, now: Self.now)
    #expect(snapshot == .init(noData: false, needsLoad: true, canSkip: false))
  }

  private func makeLocal(
    expires: Date,
    schemaVersion: Int = NavDataCache.schemaVersion
  ) -> NavDataCache.LocalManifest {
    NavDataCache.LocalManifest(
      schemaVersion: schemaVersion,
      cycleName: "2501",
      expires: expires,
      downloadedAt: Self.now,
      cycles: DataCycles(
        nasr: CycleInfo(
          name: "2501",
          effective: Self.now.addingTimeInterval(-60 * 60 * 24 * 14),
          expires: expires
        ),
        cifp: nil
      )
    )
  }
}
