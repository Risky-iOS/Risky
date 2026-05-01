import Compression
import Foundation
import StreamingLZMA

/// Reader for the binary terrain region file format produced by the SF50
/// TOLD `DownloadNASR` tool.
///
/// File layout (all little-endian):
///
/// ```
/// Header (20 bytes):
///   0..<4    "SRTM" magic
///   4..<6    version (UInt16)            -- expected: 3
///   6..<8    resolution (UInt16)         -- samples per side, e.g. 1201
///   8..<12   tileCount (UInt32)
///   12..<14  bbox.minLat (Int16)
///   14..<16  bbox.maxLat (Int16)
///   16..<18  bbox.minLon (Int16)
///   18..<20  bbox.maxLon (Int16)
///
/// Tile index (20 bytes per tile):
///   0..<2    latitude (Int16)            -- tile SW-corner latitude
///   2..<4    longitude (Int16)           -- tile SW-corner longitude
///   4..<12   dataOffset (UInt64)         -- absolute, from start of file
///   12..<16  compressedLength (UInt32)   -- 0 means void tile
///   16..<20  uncompressedLength (UInt32)
///
/// Tile data:
///   For each non-void tile, `compressedLength` bytes of LZFSE-compressed
///   `Int16[resolution × resolution]` (row-major, north-to-south).
/// ```
///
/// The whole region is wrapped in an outer LZMA (`.xz`) layer for
/// distribution; this reader takes the already-decompressed inner bytes.
struct SRTMRegionFile: Sendable {
  /// "SRTM" in ASCII.
  private static let magic: [UInt8] = [0x53, 0x52, 0x54, 0x4D]
  private static let supportedVersion: UInt16 = 3
  private static let headerSize = 20
  private static let indexEntrySize = 20

  let regionID: String
  let resolution: Int
  let boundingBox: BoundingBox
  let entries: [TileEntry]

  /// Underlying inner-bytes blob, retained so tile decompression can
  /// slice into it without copying.
  private let payload: Data

  /// LZMA-decompresses the outer `.xz` envelope and parses the SRTM
  /// header + tile index. Tile elevation arrays are not decompressed
  /// here — that happens lazily in ``loadTile(_:)``.
  static func load(regionID: String, lzmaCompressed: Data) throws -> Self {
    let payload: Data
    do {
      payload = try Self.decompressLZMA(lzmaCompressed)
    } catch {
      throw TerrainError.lzmaDecompressionFailed(
        regionID: regionID,
        underlying: error
      )
    }

    guard payload.count >= Self.headerSize else {
      throw TerrainError.regionFormatInvalid(
        regionID: regionID,
        reason: "header truncated (\(payload.count) bytes)"
      )
    }

    guard
      payload[0] == Self.magic[0], payload[1] == Self.magic[1],
      payload[2] == Self.magic[2], payload[3] == Self.magic[3]
    else {
      throw TerrainError.regionFormatInvalid(
        regionID: regionID,
        reason: "missing SRTM magic"
      )
    }

    let version = readUInt16(payload, at: 4)
    guard version == Self.supportedVersion else {
      throw TerrainError.regionFormatInvalid(
        regionID: regionID,
        reason: "unsupported version \(version)"
      )
    }

    let resolution = Int(readUInt16(payload, at: 6))
    let tileCount = Int(readUInt32(payload, at: 8))
    let bbox = BoundingBox(
      minLatitude: Int(readInt16(payload, at: 12)),
      maxLatitude: Int(readInt16(payload, at: 14)),
      minLongitude: Int(readInt16(payload, at: 16)),
      maxLongitude: Int(readInt16(payload, at: 18))
    )
    let indexStart = Self.headerSize
    let indexEnd = indexStart + tileCount * Self.indexEntrySize

    guard payload.count >= indexEnd else {
      throw TerrainError.regionFormatInvalid(
        regionID: regionID,
        reason: "tile index truncated"
      )
    }

    var entries: [TileEntry] = []
    entries.reserveCapacity(tileCount)
    for i in 0..<tileCount {
      let base = indexStart + i * Self.indexEntrySize
      entries.append(
        TileEntry(
          southLatitude: Int(readInt16(payload, at: base)),
          westLongitude: Int(readInt16(payload, at: base + 2)),
          dataOffset: Int(readUInt64(payload, at: base + 4)),
          compressedLength: Int(readUInt32(payload, at: base + 12)),
          uncompressedLength: Int(readUInt32(payload, at: base + 16))
        )
      )
    }

    return Self(
      regionID: regionID,
      resolution: resolution,
      boundingBox: bbox,
      entries: entries,
      payload: payload
    )
  }

  // MARK: - Decompression helpers

  private static func decompressLZMA(_ data: Data) throws -> Data {
    try data.lzmaFileDecompressed()
  }

  private static func decompressLZFSE(
    _ compressed: Data,
    uncompressedLength: Int,
    tileLatitude: Int,
    tileLongitude: Int
  ) throws -> [Int16] {
    var bytes = [UInt8](repeating: 0, count: uncompressedLength)
    let written = compressed.withUnsafeBytes { src -> Int in
      guard let base = src.baseAddress else { return 0 }
      return compression_decode_buffer(
        &bytes,
        uncompressedLength,
        base.assumingMemoryBound(to: UInt8.self),
        compressed.count,
        nil,
        COMPRESSION_LZFSE
      )
    }
    guard written == uncompressedLength else {
      throw TerrainError.lzfseDecompressionFailed(
        tileLatitude: tileLatitude,
        tileLongitude: tileLongitude
      )
    }

    let sampleCount = uncompressedLength / MemoryLayout<Int16>.size
    var samples = [Int16](repeating: 0, count: sampleCount)
    bytes.withUnsafeBufferPointer { src in
      samples.withUnsafeMutableBufferPointer { dst in
        _ = src.baseAddress.flatMap { srcBase in
          dst.baseAddress.map { dstBase in
            memcpy(dstBase, srcBase, uncompressedLength)
          }
        }
      }
    }
    return samples
  }

  // MARK: - Little-endian readers

  private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private static func readInt16(_ data: Data, at offset: Int) -> Int16 {
    Int16(bitPattern: readUInt16(data, at: offset))
  }

  private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }

  private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for i in 0..<8 {
      value |= UInt64(data[offset + i]) << (8 * i)
    }
    return value
  }

  // MARK: - Instance methods

  /// Locates the tile entry covering the given degree cell and decodes
  /// it. Returns `nil` if the region doesn't contain that cell.
  func loadTile(latitude: Int, longitude: Int) throws -> TerrainTile? {
    guard
      let entry = entries.first(
        where: { $0.southLatitude == latitude && $0.westLongitude == longitude }
      )
    else {
      return nil
    }
    return try decodeTile(entry: entry)
  }

  // MARK: - Tile decoding

  private func decodeTile(entry: TileEntry) throws -> TerrainTile {
    let totalSamples = resolution * resolution
    if entry.compressedLength == 0 || entry.uncompressedLength == 0 {
      return TerrainTile(
        southLatitude: entry.southLatitude,
        westLongitude: entry.westLongitude,
        resolution: resolution,
        storage: [Int16](repeating: TerrainTile.voidValue, count: totalSamples),
        isVoid: true
      )
    }

    guard entry.dataOffset + entry.compressedLength <= payload.count else {
      throw TerrainError.regionFormatInvalid(
        regionID: regionID,
        reason: "tile data extends past end of payload"
      )
    }

    let compressed = payload.subdata(
      in: entry.dataOffset..<(entry.dataOffset + entry.compressedLength)
    )

    let elevations = try Self.decompressLZFSE(
      compressed,
      uncompressedLength: entry.uncompressedLength,
      tileLatitude: entry.southLatitude,
      tileLongitude: entry.westLongitude
    )

    guard elevations.count == totalSamples else {
      throw TerrainError.regionFormatInvalid(
        regionID: regionID,
        reason:
          "tile sample count \(elevations.count) ≠ resolution² \(totalSamples)"
      )
    }

    return TerrainTile(
      southLatitude: entry.southLatitude,
      westLongitude: entry.westLongitude,
      resolution: resolution,
      storage: elevations,
      isVoid: false
    )
  }

  struct TileEntry: Sendable {
    let southLatitude: Int
    let westLongitude: Int
    let dataOffset: Int
    let compressedLength: Int
    let uncompressedLength: Int
  }

  /// Inclusive integer-degree bounding box of every tile in the region.
  struct BoundingBox: Sendable, Codable, Equatable {
    let minLatitude: Int
    let maxLatitude: Int
    let minLongitude: Int
    let maxLongitude: Int

    /// Whether the (latitude, longitude) cell falls inside the box.
    /// Both edges are inclusive on the south and west sides; the north
    /// and east sides extend one degree beyond `maxLatitude` /
    /// `maxLongitude` (the northern / eastern edges of the
    /// last-included tile).
    func contains(latitude: Double, longitude: Double) -> Bool {
      let southLat = Double(minLatitude)
      let northLat = Double(maxLatitude) + 1.0
      let westLon = Double(minLongitude)
      let eastLon = Double(maxLongitude) + 1.0
      return latitude >= southLat && latitude <= northLat
        && longitude >= westLon && longitude <= eastLon
    }
  }
}
