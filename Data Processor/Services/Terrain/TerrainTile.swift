import Foundation

/// A 1° × 1° SRTM elevation grid in memory. Samples are organized
/// row-major, with row 0 at the **north** edge and column 0 at the **west**
/// edge — the SRTM convention.
struct TerrainTile: Sendable {
  /// SRTM void marker. Sentinel value indicating "no data" (typically
  /// over water).
  static let voidValue: Int16 = -32_768

  /// Latitude of the tile's south edge, in integer degrees.
  let southLatitude: Int

  /// Longitude of the tile's west edge, in integer degrees.
  let westLongitude: Int

  /// Number of samples per side. SRTM3 tiles are 1201, SRTM1 are 3601.
  let resolution: Int

  /// Row-major elevation samples, length `resolution × resolution`.
  let storage: [Int16]

  /// Whether this tile is entirely void (e.g. open ocean).
  let isVoid: Bool

  /// Elevation at the sample nearest the given coordinate, in meters.
  /// Returns `nil` if the coordinate falls outside this tile or the
  /// nearest sample is void.
  func elevationMeters(latitude: Double, longitude: Double) -> Double? {
    guard isVoid == false else { return nil }
    guard contains(latitude: latitude, longitude: longitude) else { return nil }

    let dLat = latitude - Double(southLatitude)
    let dLon = longitude - Double(westLongitude)
    let span = Double(resolution - 1)

    // Row 0 is north edge → row = (1 - dLat) * span (clamped).
    let row = min(max(Int((1.0 - dLat) * span + 0.5), 0), resolution - 1)
    let col = min(max(Int(dLon * span + 0.5), 0), resolution - 1)

    let value = storage[row * resolution + col]
    return value == Self.voidValue ? nil : Double(value)
  }

  /// Inclusive containment check on the tile's 1° × 1° box.
  func contains(latitude: Double, longitude: Double) -> Bool {
    let south = Double(southLatitude)
    let north = south + 1.0
    let west = Double(westLongitude)
    let east = west + 1.0
    return latitude >= south && latitude <= north
      && longitude >= west && longitude <= east
  }
}
