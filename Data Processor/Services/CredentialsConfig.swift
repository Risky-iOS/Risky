import Foundation

/// Reads credentials from `Info.plist` (populated by `Credentials.xcconfig`).
///
/// Each ``Key`` corresponds to an entry the user is expected to provide in
/// `Data Processor/Credentials.xcconfig`. Missing or unsubstituted entries
/// (those still containing the literal `$(KEY)`) come back as `nil`.
enum CredentialsConfig {
  /// Default public R2 URL used by SF50 TOLD's terrain pipeline. Risky
  /// reads from the same bucket. Override via `RISKY_TERRAIN_PUBLIC_URL`
  /// only if redirecting to a different terrain source.
  static let defaultTerrainPublicURL =
    "https://pub-becd30c7b4e24860bee04cbbab788fb3.r2.dev"

  /// Default manifest object key inside the terrain bucket.
  static let defaultTerrainManifestPath = "terrain/terrain-manifest.json"

  static func validateRequired() -> [String] {
    Key.allRequired.filter { self[$0] == nil }.map(\.rawValue)
  }

  static subscript(key: Key) -> String? {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String,
      !value.isEmpty,
      !value.hasPrefix("$(")
    else { return nil }
    return value
  }

  enum Key: String, CaseIterable {
    case terrainPublicURL = "RISKY_TERRAIN_PUBLIC_URL"
    case terrainManifestPath = "RISKY_TERRAIN_MANIFEST_PATH"
    case githubToken = "GITHUB_TOKEN"
    case githubOwner = "RISKY_GITHUB_OWNER"
    case githubRepo = "RISKY_GITHUB_REPO"

    static let allRequired: [Self] = [
      .githubToken,
      .githubOwner,
      .githubRepo
    ]
  }
}
