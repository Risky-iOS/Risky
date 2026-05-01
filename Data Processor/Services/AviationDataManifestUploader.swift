import Foundation
import RiskyCommon

/// Builds an ``AviationDataManifest`` for `output` and uploads it to
/// `risky-data/manifest.json` via `uploader`.
///
/// Called after a successful payload upload so the manifest always points
/// at a payload that already exists in the data repo.
func uploadAviationDataManifest(
  for output: NavDataProcessor.Output,
  uploader: GitHubUploader
) async throws {
  let manifest = AviationDataManifest(
    latestCycleName: output.cycleName,
    payloadPath: "risky-data/\(output.cycleName).plist.lzma",
    cycles: output.cycles,
    ourAirportsLastUpdated: output.ourAirportsLastUpdated,
    generatedAt: Date()
  )

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  let data = try encoder.encode(manifest)

  let tempFile = FileManager.default.temporaryDirectory
    .appending(path: "manifest-\(output.cycleName)-\(UUID().uuidString).json")
  try data.write(to: tempFile, options: .atomic)
  defer { try? FileManager.default.removeItem(at: tempFile) }

  try await uploader.uploadFile(
    at: tempFile,
    toPath: "risky-data/manifest.json",
    commitMessage: "Update manifest for cycle \(output.cycleName)"
  )
}
