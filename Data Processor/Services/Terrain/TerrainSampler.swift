import Foundation
import Logging

/// Computes the FAA Part 95 mountainous-airport flag for a given coordinate.
///
/// Per CLAUDE.md and FAA Order 8260.3: an area is mountainous when the
/// **terrain elevation differential exceeds 3,000 ft within 10 NM**. We
/// sample the terrain at a regular grid of points inside the 10-NM circle,
/// track the min and max elevations, and compare the differential against
/// the threshold.
struct TerrainSampler {
  /// Mountainous threshold in feet (FAA Part 95 / Order 8260.3).
  static let mountainousDifferentialFt: Double = 3_000

  /// Search radius in nautical miles (FAA Part 95 / Order 8260.3).
  static let searchRadiusNM: Double = 10

  /// Sample grid spacing in nautical miles. ~250 m spacing — fine enough
  /// to catch a single peak, coarse enough to keep the work bounded
  /// (~3,300 samples per airport).
  static let sampleSpacingNM: Double = 0.135

  /// Conversions.
  private static let metersPerNM: Double = 1_852.0
  private static let feetPerMeter: Double = 3.28084
  private static let earthRadiusM: Double = 6_371_000

  let catalog: R2TerrainCatalog
  let logger: Logger

  private static func sample(
    latitude: Double,
    longitude: Double,
    in tiles: [TerrainTile]
  ) -> Double? {
    let intLat = Int(latitude.rounded(.down))
    let intLon = Int(longitude.rounded(.down))
    guard
      let tile = tiles.first(
        where: { $0.southLatitude == intLat && $0.westLongitude == intLon }
      )
    else { return nil }
    return tile.elevationMeters(latitude: latitude, longitude: longitude)
  }

  private static func greatCircleDistanceMeters(
    fromLat: Double,
    fromLon: Double,
    toLat: Double,
    toLon: Double
  ) -> Double {
    let phi1 = fromLat * .pi / 180.0
    let phi2 = toLat * .pi / 180.0
    let dPhi = (toLat - fromLat) * .pi / 180.0
    let dLam = (toLon - fromLon) * .pi / 180.0
    let a =
      sin(dPhi / 2) * sin(dPhi / 2)
      + cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadiusM * c
  }

  /// Determines whether the airport at `(latitude, longitude, elevation)`
  /// sits in mountainous terrain.
  ///
  /// Returns:
  /// - `true` if a sufficient elevation differential is found.
  /// - `false` if the surrounding terrain is contained within the
  ///   threshold, **or** if the catalog has no terrain data covering this
  ///   coordinate (a non-fatal failure mode — typical for international
  ///   airports outside the SRTM region files).
  func isMountainous(
    latitude: Double,
    longitude: Double,
    airportElevationMeters: Double
  ) async -> Bool {
    let radiusM = Self.searchRadiusNM * Self.metersPerNM
    let degLat = (radiusM / Self.earthRadiusM) * 180.0 / .pi
    let cosLat = cos(latitude * .pi / 180.0)
    guard cosLat > 0.0001 else { return false }  // near a pole — give up
    let degLon = degLat / cosLat

    // Resolve every tile covering the airport's bbox in a single actor
    // hop, then sample the grid locally. Without this batch step the
    // ~3,000 samples per airport would each block on the catalog actor.
    let tiles: [TerrainTile]
    do {
      tiles = try await catalog.tiles(
        minLatitude: latitude - degLat,
        maxLatitude: latitude + degLat,
        minLongitude: longitude - degLon,
        maxLongitude: longitude + degLon
      )
    } catch {
      let detail =
        (error as? LocalizedError)?.failureReason
        ?? error.localizedDescription
      logger.warning(
        "Terrain bbox lookup failed at (\(latitude), \(longitude)): \(detail)"
      )
      return false
    }
    guard !tiles.isEmpty else { return false }

    let radiusM2 = radiusM * radiusM
    let stepDeg = Self.sampleSpacingNM * Self.metersPerNM / Self.earthRadiusM * 180.0 / .pi

    // Always include the airport's own elevation in the differential.
    var minMeters = airportElevationMeters
    var maxMeters = airportElevationMeters
    var samplesTaken = 0

    // Walk a square grid; reject samples outside the circle.
    var dLat = -degLat
    while dLat <= degLat {
      var dLon = -degLon
      while dLon <= degLon {
        let sampleLat = latitude + dLat
        let sampleLon = longitude + dLon
        let meters = Self.greatCircleDistanceMeters(
          fromLat: latitude,
          fromLon: longitude,
          toLat: sampleLat,
          toLon: sampleLon
        )
        if meters * meters <= radiusM2 {
          if let elevation = Self.sample(
            latitude: sampleLat,
            longitude: sampleLon,
            in: tiles
          ) {
            if elevation < minMeters { minMeters = elevation }
            if elevation > maxMeters { maxMeters = elevation }
            samplesTaken += 1
          }
        }
        dLon += stepDeg
      }
      dLat += stepDeg
    }

    // If we couldn't sample anything (e.g. no region covers this airport),
    // we have no signal — return false.
    guard samplesTaken > 0 else {
      return false
    }

    let differentialFt = (maxMeters - minMeters) * Self.feetPerMeter
    return differentialFt > Self.mountainousDifferentialFt
  }
}
