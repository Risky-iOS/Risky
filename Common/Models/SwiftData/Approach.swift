import Foundation
import SwiftData

/// An instrument approach procedure published for a specific runway/airport. Holds per-category
/// minimums (ceiling and visibility).
@Model
public final class Approach {
  /// Type of instrument approach (ILS, RNAV, VOR, etc.).
  public var type = ApproachType.ILS

  /// Airport this approach serves.
  public var airport: Airport?
  /// Runway end this approach terminates on, if applicable.
  public var runway: Runway?

  private var _categoryACeilingMeters: Double?
  private var _categoryBCeilingMeters: Double?
  private var _categoryCCeilingMeters: Double?
  private var _categoryDCeilingMeters: Double?

  private var _categoryAVisibilityMeters: Double?
  private var _categoryBVisibilityMeters: Double?
  private var _categoryCVisibilityMeters: Double?
  private var _categoryDVisibilityMeters: Double?

  /// Creates an approach for the given airport (and optional runway).
  public init(type: ApproachType, airport: Airport, runway: Runway? = nil) {
    self.type = type
    self.airport = airport
    self.runway = runway
  }

  /// Returns the published ceiling minimum for the given approach category, if known.
  public func ceiling(for category: ApproachCategory) -> Measurement<UnitLength>? {
    ceilingMeters(for: category).map { Measurement(value: $0, unit: .meters) }
  }

  /// Sets the published ceiling minimum for the given approach category.
  public func setCeiling(_ value: Measurement<UnitLength>?, for category: ApproachCategory) {
    let meters = value?.converted(to: .meters).value
    switch category {
      case .A: _categoryACeilingMeters = meters
      case .B: _categoryBCeilingMeters = meters
      case .C: _categoryCCeilingMeters = meters
      case .D: _categoryDCeilingMeters = meters
    }
  }

  /// Returns the published visibility minimum for the given approach category, if known.
  public func visibility(for category: ApproachCategory) -> Measurement<UnitLength>? {
    visibilityMeters(for: category).map { Measurement(value: $0, unit: .meters) }
  }

  /// Sets the published visibility minimum for the given approach category.
  public func setVisibility(_ value: Measurement<UnitLength>?, for category: ApproachCategory) {
    let meters = value?.converted(to: .meters).value
    switch category {
      case .A: _categoryAVisibilityMeters = meters
      case .B: _categoryBVisibilityMeters = meters
      case .C: _categoryCVisibilityMeters = meters
      case .D: _categoryDVisibilityMeters = meters
    }
  }

  private func ceilingMeters(for category: ApproachCategory) -> Double? {
    switch category {
      case .A: _categoryACeilingMeters
      case .B: _categoryBCeilingMeters
      case .C: _categoryCCeilingMeters
      case .D: _categoryDCeilingMeters
    }
  }

  private func visibilityMeters(for category: ApproachCategory) -> Double? {
    switch category {
      case .A: _categoryAVisibilityMeters
      case .B: _categoryBVisibilityMeters
      case .C: _categoryCVisibilityMeters
      case .D: _categoryDVisibilityMeters
    }
  }
}
