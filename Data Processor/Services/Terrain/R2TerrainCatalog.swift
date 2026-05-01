import Foundation
import Logging

/// Caches terrain region files downloaded from R2 and their decoded tiles.
///
/// The Data Processor consults this actor for every airport during the
/// mountainous-flag computation. To avoid downloading every region in the
/// manifest just to discover which one covers a given airport, we maintain
/// a disk-backed bounding-box cache: once a region has been downloaded
/// (here or in a prior run) we know its lat/lon extents and can skip it
/// for queries that fall outside.
actor R2TerrainCatalog {
  /// Continent-prior bounding boxes used to pick a region before its real
  /// bbox is known. The actual file's bbox replaces this once downloaded;
  /// these only steer the first-touch ordering. Slightly oversized to
  /// avoid false-negatives at boundaries.
  private static let continentPriors: [String: SRTMRegionFile.BoundingBox] = [
    "na": .init(minLatitude: 5, maxLatitude: 84, minLongitude: -179, maxLongitude: -50),
    "sa": .init(minLatitude: -60, maxLatitude: 14, minLongitude: -90, maxLongitude: -33),
    "eu": .init(minLatitude: 34, maxLatitude: 72, minLongitude: -25, maxLongitude: 45),
    "af": .init(minLatitude: -35, maxLatitude: 38, minLongitude: -20, maxLongitude: 52),
    "as": .init(minLatitude: -10, maxLatitude: 80, minLongitude: 25, maxLongitude: 180),
    "au": .init(minLatitude: -55, maxLatitude: -9, minLongitude: 110, maxLongitude: 180),
    "oc": .init(minLatitude: -55, maxLatitude: 30, minLongitude: 130, maxLongitude: 180),
    "me": .init(minLatitude: 12, maxLatitude: 45, minLongitude: 25, maxLongitude: 65),
    "io": .init(minLatitude: -10, maxLatitude: 30, minLongitude: 30, maxLongitude: 110),
    "ma": .init(minLatitude: 13, maxLatitude: 40, minLongitude: -28, maxLongitude: -12),
    "aq": .init(minLatitude: -90, maxLatitude: -60, minLongitude: -180, maxLongitude: 180)
  ]

  /// Maximum decoded tiles to keep in memory at once. Each tile is roughly
  /// 1201×1201 Int16 ≈ 2.9 MB; 32 tiles ≈ 90 MB.
  private static let tileCacheLimit = 32

  /// How long to back off after a transient failure before allowing a
  /// region to be re-attempted by a later airport. Permanent failures
  /// stay disabled for the entire run.
  private static let transientCooldown: TimeInterval = 60

  private let downloader: R2Downloader
  private let manifestPath: String
  private let logger: Logger
  private let bboxCache: RegionBoundingBoxCache

  private var manifest: Manifest?
  private var loadedRegions: [String: SRTMRegionFile] = [:]
  private var loadingTasks: [String: Task<SRTMRegionFile, any Swift.Error>] = [:]
  /// Regions whose load failed permanently this run (parse error, 404,
  /// etc.). Skipped for the rest of the run.
  private var permanentlyFailedRegions: Set<String> = []
  /// Regions whose retry budget was exhausted on a transient failure,
  /// keyed to the time of that exhaustion. They become eligible again
  /// after ``transientCooldown`` seconds — the next airport that needs
  /// the region will try once more.
  private var lastTransientFailure: [String: Date] = [:]
  /// Decoded-tile cache. The grid sampler hits the same 1°×1° tile for
  /// thousands of consecutive samples around an airport, so caching the
  /// decoded `[Int16]` cuts LZFSE work from `O(samples)` to `O(tiles)`.
  private var tileCache: [TileKey: TerrainTile] = [:]
  private var tileCacheOrder: [TileKey] = []

  init(
    downloader: R2Downloader,
    manifestPath: String = "terrain/terrain-manifest.json",
    cacheDirectory: URL,
    logger: Logger
  ) {
    self.downloader = downloader
    self.manifestPath = manifestPath
    self.logger = logger
    self.bboxCache = RegionBoundingBoxCache(
      directory: cacheDirectory,
      logger: logger
    )
  }

  private static func containsTile(
    _ region: SRTMRegionFile,
    latitude: Double,
    longitude: Double
  ) -> Bool {
    let intLat = Int(latitude.rounded(.down))
    let intLon = Int(longitude.rounded(.down))
    return region.entries.contains {
      $0.southLatitude == intLat && $0.westLongitude == intLon
    }
  }

  /// Loads the manifest if not already cached. Idempotent.
  func ensureManifest() async throws -> Manifest {
    if let manifest { return manifest }

    let data: Data
    do {
      data = try await downloader.data(at: manifestPath)
    } catch {
      throw TerrainError.manifestFetchFailed(underlying: error)
    }

    do {
      let manifest = try JSONDecoder().decode(Manifest.self, from: data)
      self.manifest = manifest
      logger.notice(
        "Loaded terrain manifest with \(manifest.regions.count) region(s)"
      )
      return manifest
    } catch {
      throw TerrainError.manifestFetchFailed(underlying: error)
    }
  }

  /// Persist any new bounding-box entries discovered during this run.
  func flushBoundingBoxCache() async {
    await bboxCache.flush()
  }

  /// Returns the region containing the given coordinate, or `nil` if no
  /// region in the manifest covers it.
  ///
  /// Lookup order:
  /// 1. **Already-loaded regions in memory** — instant.
  /// 2. **Bounding-box cache (disk)** — if a region's cached bbox covers
  ///    the coord, download (and cache) just that region.
  /// 3. **Unknown regions** — for any region we have no bbox cache entry
  ///    for, download and cache its bbox. If it covers the coord, return
  ///    it; otherwise the bbox is now in cache so we won't re-download.
  func region(forLatitude latitude: Double, longitude: Double) async throws -> SRTMRegionFile? {
    let manifest = try await ensureManifest()

    // 1. In-memory hits first.
    for region in loadedRegions.values
    where region.boundingBox.contains(
      latitude: latitude,
      longitude: longitude
    ) {
      if Self.containsTile(region, latitude: latitude, longitude: longitude) {
        return region
      }
    }

    // 2. Cached bboxes that cover the coord — download just those.
    for region in manifest.regions {
      if loadedRegions[region.id] != nil { continue }
      if isRegionDisabled(region.id) { continue }
      guard
        let bbox = await bboxCache.boundingBox(
          forRegionID: region.id,
          expectedSizeBytes: region.sizeBytes
        )
      else { continue }
      guard bbox.contains(latitude: latitude, longitude: longitude) else { continue }
      if let loaded = try await loadOrFail(region: region) {
        if Self.containsTile(loaded, latitude: latitude, longitude: longitude) {
          return loaded
        }
      }
    }

    // 3. Regions with no cached bbox. Try those whose continent prior
    // covers the coord first — for the common case of US airports we
    // download "na" before iterating Eurasia/etc.
    let unknownRegions = manifest.regions.filter { region in
      loadedRegions[region.id] == nil && !isRegionDisabled(region.id)
    }
    let priorMatches = unknownRegions.filter { region in
      Self.continentPriors[region.id]?
        .contains(latitude: latitude, longitude: longitude) == true
    }
    let priorMisses = unknownRegions.filter { region in
      Self.continentPriors[region.id]?
        .contains(latitude: latitude, longitude: longitude) != true
    }
    for region in priorMatches + priorMisses {
      if loadedRegions[region.id] != nil { continue }
      if isRegionDisabled(region.id) { continue }
      let cached = await bboxCache.boundingBox(
        forRegionID: region.id,
        expectedSizeBytes: region.sizeBytes
      )
      if cached != nil { continue }  // already evaluated in step 2
      if let loaded = try await loadOrFail(region: region),
        Self.containsTile(loaded, latitude: latitude, longitude: longitude)
      {
        return loaded
      }
    }

    return nil
  }

  /// Returns the decoded tile for `(intLat, intLon)` from `region`, using
  /// an in-memory LRU cache so the grid sampler doesn't re-LZFSE the same
  /// tile thousands of times. Returns `nil` if the region has no tile at
  /// that cell (over open ocean, etc.).
  func tile(in region: SRTMRegionFile, latitude: Int, longitude: Int) throws -> TerrainTile? {
    let key = TileKey(regionID: region.regionID, latitude: latitude, longitude: longitude)
    if let cached = tileCache[key] {
      return cached
    }
    guard let tile = try region.loadTile(latitude: latitude, longitude: longitude) else {
      return nil
    }
    tileCache[key] = tile
    tileCacheOrder.append(key)
    while tileCacheOrder.count > Self.tileCacheLimit {
      let evicted = tileCacheOrder.removeFirst()
      tileCache.removeValue(forKey: evicted)
    }
    return tile
  }

  /// Returns every decoded tile whose 1° cell intersects the lat/lon
  /// rectangle `[minLat, maxLat] × [minLon, maxLon]`. Resolves the
  /// covering region(s) once and caches each tile, so the caller can
  /// iterate sample points without making actor hops per sample.
  ///
  /// Tiles in the bbox that aren't covered by any region (e.g. the
  /// rectangle straddles open ocean) are simply omitted.
  func tiles(
    minLatitude: Double,
    maxLatitude: Double,
    minLongitude: Double,
    maxLongitude: Double
  ) async throws -> [TerrainTile] {
    let cellSouth = Int(minLatitude.rounded(.down))
    let cellNorth = Int(maxLatitude.rounded(.down))
    let cellWest = Int(minLongitude.rounded(.down))
    let cellEast = Int(maxLongitude.rounded(.down))

    var tiles: [TerrainTile] = []
    for lat in cellSouth...cellNorth {
      for lon in cellWest...cellEast {
        let cellLatMid = Double(lat) + 0.5
        let cellLonMid = Double(lon) + 0.5
        guard
          let region = try await region(
            forLatitude: cellLatMid,
            longitude: cellLonMid
          )
        else { continue }
        if let tile = try tile(in: region, latitude: lat, longitude: lon) {
          tiles.append(tile)
        }
      }
    }
    return tiles
  }

  /// Whether `regionID` is currently disabled — either permanently failed
  /// or inside the transient-cooldown window.
  private func isRegionDisabled(_ regionID: String) -> Bool {
    if permanentlyFailedRegions.contains(regionID) { return true }
    if let lastFailure = lastTransientFailure[regionID],
      Date().timeIntervalSince(lastFailure) < Self.transientCooldown
    {
      return true
    }
    return false
  }

  /// Wraps `load(region:)` so a region whose load fails this attempt
  /// doesn't immediately get re-attempted by every other airport. A
  /// permanent failure (parse error, 404) disables it for the run; a
  /// transient failure (network drop) only suppresses retry for
  /// ``transientCooldown`` seconds, after which the next airport will
  /// try again — the network may have recovered by then.
  private func loadOrFail(region: Region) async throws -> SRTMRegionFile? {
    do {
      return try await load(region: region)
    } catch {
      let classification = classify(error)
      let detail =
        (error as? LocalizedError)?.failureReason
        ?? error.localizedDescription
      switch classification {
        case .transient, .retryAfter:
          lastTransientFailure[region.id] = Date()
          logger.warning(
            "Region “\(region.id)” transient failure — backing off for \(Int(Self.transientCooldown))s before retry: \(detail)"
          )
        case .permanent:
          permanentlyFailedRegions.insert(region.id)
          logger.warning(
            "Region “\(region.id)” failed permanently — skipping for the rest of this run: \(detail)"
          )
      }
      return nil
    }
  }

  private func load(region: Region) async throws -> SRTMRegionFile {
    if let cached = loadedRegions[region.id] { return cached }
    if let inFlight = loadingTasks[region.id] {
      return try await inFlight.value
    }

    let task = Task<SRTMRegionFile, any Swift.Error> {
      try await self.fetchAndParse(region: region)
    }
    loadingTasks[region.id] = task

    do {
      let parsed = try await task.value
      loadedRegions[region.id] = parsed
      await bboxCache.record(
        regionID: region.id,
        sizeBytes: region.sizeBytes,
        boundingBox: parsed.boundingBox
      )
      loadingTasks.removeValue(forKey: region.id)
      return parsed
    } catch {
      loadingTasks.removeValue(forKey: region.id)
      throw error
    }
  }

  private func fetchAndParse(region: Region) async throws -> SRTMRegionFile {
    logger.notice("Downloading terrain region “\(region.id)” (\(region.sizeBytes) bytes)…")
    let fileURL: URL
    do {
      fileURL = try await downloader.downloadToTemporaryFile(
        objectKey: "terrain/\(region.filename)"
      )
    } catch {
      throw TerrainError.regionFetchFailed(regionID: region.id, underlying: error)
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let raw: Data
    do {
      raw = try Data(contentsOf: fileURL, options: [.alwaysMapped])
    } catch {
      throw TerrainError.regionFetchFailed(regionID: region.id, underlying: error)
    }
    return try SRTMRegionFile.load(regionID: region.id, lzmaCompressed: raw)
  }

  /// Manifest entry as produced by SF50 TOLD's terrain pipeline.
  struct Region: Sendable, Decodable {
    let id: String
    let filename: String
    let sizeBytes: Int
  }

  struct Manifest: Sendable, Decodable {
    let version: Int
    let generatedAt: String?
    let regions: [Region]
  }

  private struct TileKey: Hashable {
    let regionID: String
    let latitude: Int
    let longitude: Int
  }
}
