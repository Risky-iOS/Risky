import Foundation
import Logging

/// Uploads the compressed airport plist to a GitHub repository via the
/// REST Contents API.
///
/// The Risky iOS app fetches the latest cycle by reading the contents of
/// the configured repository at runtime. This uploader is invoked at the
/// end of every successful Data Processor run.
actor GitHubUploader {
  private static let baseURL = URL(string: "https://api.github.com")!

  private let token: String
  private let owner: String
  private let repo: String
  private let logger: Logger

  init(token: String, owner: String, repo: String, logger: Logger) {
    self.token = token
    self.owner = owner
    self.repo = repo
    self.logger = logger
  }

  /// Convenience initializer reading credentials from `Info.plist`.
  init(logger: Logger) throws {
    guard let token = CredentialsConfig[.githubToken] else {
      throw GitHubUploadError.missingToken
    }
    guard let owner = CredentialsConfig[.githubOwner] else {
      throw CredentialsError.missing(key: CredentialsConfig.Key.githubOwner.rawValue)
    }
    guard let repo = CredentialsConfig[.githubRepo] else {
      throw CredentialsError.missing(key: CredentialsConfig.Key.githubRepo.rawValue)
    }
    self.init(token: token, owner: owner, repo: repo, logger: logger)
  }

  /// Validate the configured token by hitting `/user`. Returns on success;
  /// throws ``GitHubUploadError`` on auth failure.
  func validateToken() async throws {
    let url = Self.baseURL.appending(path: "user")
    var request = URLRequest(url: url)
    configure(&request)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw GitHubUploadError.unexpectedResponse(reason: "non-HTTP response")
    }
    guard http.statusCode == 200 else {
      throw GitHubUploadError.authFailed(statusCode: http.statusCode)
    }
  }

  /// Upload `localFile` to `repoPath` on the configured branch.
  ///
  /// If a file already exists at that path the existing SHA is fetched and
  /// included in the request, so the API performs an update rather than a
  /// (rejected) create.
  func uploadFile(
    at localFile: URL,
    toPath repoPath: String,
    commitMessage: String,
    branch: String = "main",
    onProgress: (@Sendable (Double) async -> Void)? = nil
  ) async throws {
    await onProgress?(0.0)
    logger.info("Uploading \(localFile.lastPathComponent) to \(owner)/\(repo):\(repoPath)")

    let fileData = try Data(contentsOf: localFile)
    let base64 = fileData.base64EncodedString()
    let existingSHA = try await existingFileSHA(path: repoPath, branch: branch)

    if existingSHA != nil {
      logger.notice("Overwriting existing remote file at \(repoPath)")
    }

    let url = Self.baseURL.appending(path: "repos/\(owner)/\(repo)/contents/\(repoPath)")
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    configure(&request)

    var body: [String: Any] = [
      "message": commitMessage,
      "content": base64,
      "branch": branch
    ]
    if let existingSHA { body["sha"] = existingSHA }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw GitHubUploadError.unexpectedResponse(reason: "non-HTTP response")
    }

    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8)
      switch http.statusCode {
        case 401:
          throw GitHubUploadError.authFailed(statusCode: 401)
        case 403, 404:
          throw GitHubUploadError.releaseCreationFailed(
            statusCode: http.statusCode,
            body: body
          )
        default:
          throw GitHubUploadError.assetUploadFailed(
            statusCode: http.statusCode,
            body: body
          )
      }
    }

    await onProgress?(1.0)
    logger.notice("Uploaded \(localFile.lastPathComponent) (\(fileData.count) bytes)")
  }

  private func existingFileSHA(path: String, branch: String) async throws -> String? {
    let escaped =
      path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    guard
      let url = URL(
        string: "\(Self.baseURL)/repos/\(owner)/\(repo)/contents/\(escaped)?ref=\(branch)"
      )
    else { return nil }

    var request = URLRequest(url: url)
    configure(&request)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      return nil
    }
    if http.statusCode == 404 { return nil }
    guard http.statusCode == 200 else {
      throw GitHubUploadError.unexpectedResponse(
        reason: "GET contents returned HTTP \(http.statusCode)"
      )
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GitHubUploadError.unexpectedResponse(reason: "non-object JSON")
    }
    return json["sha"] as? String
  }

  private func configure(_ request: inout URLRequest) {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
  }
}
