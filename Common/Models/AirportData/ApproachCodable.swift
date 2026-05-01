import Foundation

/// A published approach procedure at an airport.
///
/// Approaches are stored at the airport level. ``runwayIdentifier`` links to
/// a specific runway when the approach has a published runway (e.g. `I19L`
/// → `19L`), or stays `nil` for circling approaches like KASE's `RNV-F`.
///
/// Mirrors ``RiskyCommon.Approach``. Per-category minimums are flattened
/// to optional ``CategoryMinimums`` so the codable form is dense (categories
/// without published minimums are simply omitted from the array).
public struct ApproachCodable: Codable, Sendable {
  /// Approach type as published, e.g. ILS, RNAV, VOR.
  public let type: ApproachType

  /// Runway identifier (e.g. `"19L"`) when the approach terminates at a
  /// specific runway. `nil` for circling approaches.
  public let runwayIdentifier: String?

  /// Per-category minimums (A through D). May contain fewer than four
  /// entries if not every category has published minimums.
  public let minimums: [CategoryMinimums]

  public init(
    type: ApproachType,
    runwayIdentifier: String?,
    minimums: [CategoryMinimums]
  ) {
    self.type = type
    self.runwayIdentifier = runwayIdentifier
    self.minimums = minimums
  }
}

extension ApproachCodable {
  /// Decision-altitude / decision-height pair for one approach category.
  public struct CategoryMinimums: Codable, Sendable {
    /// Aircraft approach category (A, B, C, or D).
    public let category: ApproachCategory

    /// Decision-altitude ceiling above the runway threshold, in meters.
    /// `nil` for circling-only minimums or when not published.
    public let ceilingMeters: Double?

    /// Required visibility in meters.
    /// `nil` when not published for this category.
    public let visibilityMeters: Double?

    public init(
      category: ApproachCategory,
      ceilingMeters: Double?,
      visibilityMeters: Double?
    ) {
      self.category = category
      self.ceilingMeters = ceilingMeters
      self.visibilityMeters = visibilityMeters
    }
  }
}
