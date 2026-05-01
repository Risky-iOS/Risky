import Foundation

// MARK: - NASR

public protocol NASRProcessorError: LocalizedError, Sendable {}

public enum NASRError: NASRProcessorError {
  case downloadFailed(underlying: any Error)
  case parseFailed(underlying: any Error)
  case unexpectedCycle(name: String)

  public var errorDescription: String? {
    String(localized: "Couldn’t process FAA NASR data.")
  }

  public var failureReason: String? {
    switch self {
      case .downloadFailed(let underlying):
        String(
          localized: "Download failed: \(underlying.localizedDescription)"
        )
      case .parseFailed(let underlying):
        String(
          localized: "Parse failed: \(underlying.localizedDescription)"
        )
      case .unexpectedCycle(let name):
        String(localized: "FAA returned an unexpected cycle “\(name)”.")
    }
  }
}

// MARK: - OurAirports

public protocol OurAirportsError: LocalizedError, Sendable {}

public enum OurAirportsLoadError: OurAirportsError {
  case downloadFailed(underlying: any Error)
  case csvParseFailed(reason: String, line: Int?)

  public var errorDescription: String? {
    String(localized: "Couldn’t process OurAirports data.")
  }

  public var failureReason: String? {
    switch self {
      case .downloadFailed(let underlying):
        String(
          localized: "Download failed: \(underlying.localizedDescription)"
        )
      case let .csvParseFailed(reason, line):
        if let line {
          String(
            localized: "CSV parse error on line \(line, format: .number): \(reason)"
          )
        } else {
          String(localized: "CSV parse error: \(reason)")
        }
    }
  }
}

// MARK: - CIFP

public protocol CIFPProcessorError: LocalizedError, Sendable {}

public enum CIFPError: CIFPProcessorError {
  case downloadFailed(underlying: any Error)
  case parseFailed(underlying: any Error)
  case unrecognizedApproachType(raw: String)

  public var errorDescription: String? {
    String(localized: "Couldn’t process FAA CIFP data.")
  }

  public var failureReason: String? {
    switch self {
      case .downloadFailed(let underlying):
        String(
          localized: "Download failed: \(underlying.localizedDescription)"
        )
      case .parseFailed(let underlying):
        String(
          localized: "Parse failed: \(underlying.localizedDescription)"
        )
      case .unrecognizedApproachType(let raw):
        String(localized: "Unrecognized approach type code “\(raw)”.")
    }
  }
}

// MARK: - Terrain

public protocol TerrainProcessorError: LocalizedError, Sendable {}

public enum TerrainError: TerrainProcessorError {
  case manifestFetchFailed(underlying: any Error)
  case regionFetchFailed(regionID: String, underlying: any Error)
  case regionFormatInvalid(regionID: String, reason: String)
  case lzmaDecompressionFailed(regionID: String, underlying: any Error)
  case lzfseDecompressionFailed(tileLatitude: Int, tileLongitude: Int)

  public var errorDescription: String? {
    String(localized: "Couldn’t load terrain data.")
  }

  public var failureReason: String? {
    switch self {
      case .manifestFetchFailed(let underlying):
        String(
          localized: "Manifest fetch failed: \(underlying.localizedDescription)"
        )
      case let .regionFetchFailed(regionID, underlying):
        String(
          localized:
            "Region “\(regionID)” fetch failed: \(underlying.localizedDescription)"
        )
      case let .regionFormatInvalid(regionID, reason):
        String(localized: "Region “\(regionID)” has an invalid format: \(reason)")
      case let .lzmaDecompressionFailed(regionID, underlying):
        String(
          localized:
            "Region “\(regionID)” LZMA decompression failed: \(underlying.localizedDescription)"
        )
      case let .lzfseDecompressionFailed(lat, lon):
        String(
          localized:
            "Tile (\(lat, format: .number), \(lon, format: .number)) LZFSE decompression failed."
        )
    }
  }
}

// MARK: - GitHub upload

public protocol GitHubUploaderError: LocalizedError, Sendable {}

public enum GitHubUploadError: GitHubUploaderError {
  case missingToken
  case authFailed(statusCode: Int)
  case releaseCreationFailed(statusCode: Int, body: String?)
  case assetUploadFailed(statusCode: Int, body: String?)
  case unexpectedResponse(reason: String)

  public var errorDescription: String? {
    String(localized: "Couldn’t upload to GitHub Releases.")
  }

  public var failureReason: String? {
    switch self {
      case .missingToken:
        String(localized: "GITHUB_TOKEN is not configured in Credentials.xcconfig.")
      case .authFailed(let code):
        String(localized: "Authentication failed (HTTP \(code, format: .number)).")
      case let .releaseCreationFailed(code, body):
        if let body {
          String(
            localized:
              "Couldn’t create release (HTTP \(code, format: .number)): \(body)"
          )
        } else {
          String(localized: "Couldn’t create release (HTTP \(code, format: .number)).")
        }
      case let .assetUploadFailed(code, body):
        if let body {
          String(
            localized:
              "Couldn’t upload asset (HTTP \(code, format: .number)): \(body)"
          )
        } else {
          String(localized: "Couldn’t upload asset (HTTP \(code, format: .number)).")
        }
      case .unexpectedResponse(let reason):
        String(localized: "Unexpected response from GitHub: \(reason)")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .missingToken:
        String(
          localized:
            "Copy Credentials.xcconfig.template to Credentials.xcconfig and set GITHUB_TOKEN."
        )
      default:
        nil
    }
  }
}

// MARK: - Configuration

public protocol ConfigurationError: LocalizedError, Sendable {}

public enum CredentialsError: ConfigurationError {
  case missing(key: String)

  public var errorDescription: String? {
    String(localized: "Missing required credential.")
  }

  public var failureReason: String? {
    switch self {
      case .missing(let key):
        String(localized: "“\(key)” is not set in Credentials.xcconfig.")
    }
  }

  public var recoverySuggestion: String? {
    String(
      localized:
        "Copy Credentials.xcconfig.template to Credentials.xcconfig and fill in every required value."
    )
  }
}
