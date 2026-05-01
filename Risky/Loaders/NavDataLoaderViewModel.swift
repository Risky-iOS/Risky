import Foundation
import Observation
import RiskyCommon

/// View model coordinating airport-data loading and the loader UI's state.
///
/// `showLoader` is the single signal the root view consults. It's `true`
/// when no payload is cached or when the cache is out of date — and
/// `false` when the user has explicitly chosen to defer an out-of-date
/// update for the rest of the session.
///
/// Modeled on SF50 TOLD's `NavDataLoaderViewModel`, simplified for Risky:
/// no `Defaults`/`Sentry`, no `ModelContainer` (the cache lives on disk),
/// schema version is read from ``NavDataCache``.
@Observable
@MainActor
final class NavDataLoaderViewModel {
  var state: NavDataLoader.State = .idle
  var error: Swift.Error?

  var noData = false
  var needsLoad = true
  var canSkip = false
  var networkIsExpensive = false
  var deferred = false

  private let loader: NavDataLoader
  private let cache: NavDataCache

  private var loadTask: Task<Void, Never>?
  private var statePollTask: Task<Void, Never>?
  private var freshnessTask: Task<Void, Never>?

  var showLoader: Bool {
    (noData || needsLoad) && !deferred
  }

  init(
    loader: NavDataLoader = NavDataLoader(),
    cache: NavDataCache = .shared,
    autostartObservation: Bool = true
  ) {
    self.loader = loader
    self.cache = cache
    if autostartObservation {
      recalculate()
      startFreshnessPoll()
    }
  }

  /// Pure freshness-decision function. Exposed so unit tests can exercise
  /// the gating table without touching the App Group container.
  static func snapshot(
    from local: NavDataCache.LocalManifest?,
    now: Date
  ) -> Snapshot {
    let noData = (local == nil)
    let schemaOutOfDate = local?.schemaVersion != NavDataCache.schemaVersion
    let dataOutOfDate = local.map { now > $0.expires } ?? true

    return Snapshot(
      noData: noData,
      needsLoad: schemaOutOfDate || dataOutOfDate,
      canSkip: !noData && !schemaOutOfDate
    )
  }

  /// Begins a download. Idempotent: a second call while a load is already
  /// in flight is ignored.
  func load() {
    guard loadTask == nil else { return }

    error = nil
    statePollTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let state = await self.loader.state
        self.state = state
        try? await Task.sleep(for: .seconds(0.25))
      }
    }

    loadTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.statePollTask?.cancel()
        self.statePollTask = nil
        self.loadTask = nil
      }
      do {
        _ = try await self.loader.load()
        self.recalculate()
      } catch {
        self.error = error
      }
    }
  }

  /// Defers the loader for the remainder of the session. Has no effect
  /// when the loader is in a non-skippable state (i.e. no payload is
  /// cached at all).
  func loadLater() {
    if canSkip { deferred = true }
  }

  private func startFreshnessPoll() {
    freshnessTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.recalculate()
        try? await Task.sleep(for: .seconds(0.5))
      }
    }
  }

  private func recalculate() {
    let snapshot = Self.snapshot(from: cache.loadLocalManifest(), now: Date())
    if noData != snapshot.noData { noData = snapshot.noData }
    if needsLoad != snapshot.needsLoad { needsLoad = snapshot.needsLoad }
    if canSkip != snapshot.canSkip { canSkip = snapshot.canSkip }
  }

  struct Snapshot: Equatable {
    let noData: Bool
    let needsLoad: Bool
    let canSkip: Bool
  }
}
