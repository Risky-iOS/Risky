import Foundation
import Logging

/// Persists per-region SRTM bounding boxes to disk so subsequent runs don't
/// have to download a region just to discover it doesn't cover the airport
/// they're looking for.
///
/// The cache is a small JSON file at
/// `~/Library/Application Support/Risky Data Processor/region-bboxes.json`.
/// Entries are keyed by `regionID` and stored alongside the manifest's
/// `sizeBytes`, which we use as a coarse "did this region change?" check —
/// if the size differs from what the manifest says, we drop the cached
/// bbox and re-fetch.
actor RegionBoundingBoxCache {
  private let fileURL: URL
  private let logger: Logger
  private var entries: [String: Entry]
  private var dirty = false

  init(directory: URL, logger: Logger) {
    self.fileURL = directory.appending(path: "region-bboxes.json")
    self.logger = logger
    self.entries = Self.load(from: fileURL, logger: logger)
  }

  private static func load(from url: URL, logger: Logger) -> [String: Entry] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode([String: Entry].self, from: data)
    } catch {
      logger.warning(
        "Couldn’t read terrain bbox cache (\(url.lastPathComponent)): \(error.localizedDescription)"
      )
      return [:]
    }
  }

  /// Returns the cached bounding box for `regionID` only if the cached
  /// size matches `expectedSizeBytes` — otherwise the cache is stale.
  func boundingBox(forRegionID regionID: String, expectedSizeBytes: Int) -> SRTMRegionFile
    .BoundingBox?
  {
    guard let entry = entries[regionID] else { return nil }
    guard entry.sizeBytes == expectedSizeBytes else {
      logger.debug(
        "Bbox cache stale for region “\(regionID)” (size \(entry.sizeBytes) → \(expectedSizeBytes))"
      )
      entries.removeValue(forKey: regionID)
      dirty = true
      return nil
    }
    return entry.boundingBox
  }

  /// Records the bounding box for `regionID`. Persists asynchronously.
  func record(
    regionID: String,
    sizeBytes: Int,
    boundingBox: SRTMRegionFile.BoundingBox
  ) {
    entries[regionID] = Entry(sizeBytes: sizeBytes, boundingBox: boundingBox)
    dirty = true
  }

  /// Flushes any pending entries to disk. Call after a batch of updates.
  func flush() {
    guard dirty else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(entries)
      try data.write(to: fileURL, options: .atomic)
      dirty = false
      logger.debug("Wrote terrain bbox cache to \(fileURL.path)")
    } catch {
      logger.warning(
        "Failed to write terrain bbox cache: \(error.localizedDescription)"
      )
    }
  }

  private struct Entry: Codable, Sendable {
    let sizeBytes: Int
    let boundingBox: SRTMRegionFile.BoundingBox
  }
}
