import Foundation
import SwiftData

/// A single runway end at an airport, with declared distances used for go/no-go assessments.
@Model
public final class Runway {
  /// Runway identifier (e.g. "28L").
  public var identifier = ""
  /// Whether the runway has runway-edge or centerline lighting.
  public var isLighted = false

  private var _lengthMeters: Double = 0
  /// Physical runway length.
  public var length: Measurement<UnitLength> {
    get { Measurement(value: _lengthMeters, unit: .meters) }
    set { _lengthMeters = newValue.converted(to: .meters).value }
  }

  private var _TORAMeters: Double = 0
  /// Take-Off Run Available.
  public var TORA: Measurement<UnitLength> {
    get { Measurement(value: _TORAMeters, unit: .meters) }
    set { _TORAMeters = newValue.converted(to: .meters).value }
  }

  private var _TODAMeters: Double = 0
  /// Take-Off Distance Available (TORA + clearway).
  public var TODA: Measurement<UnitLength> {
    get { Measurement(value: _TODAMeters, unit: .meters) }
    set { _TODAMeters = newValue.converted(to: .meters).value }
  }

  private var _LDAMeters: Double = 0
  /// Landing Distance Available.
  public var LDA: Measurement<UnitLength> {
    get { Measurement(value: _LDAMeters, unit: .meters) }
    set { _LDAMeters = newValue.converted(to: .meters).value }
  }

  /// Airport this runway belongs to.
  public var airport: Airport?

  /// Approaches that use this runway end.
  @Relationship(deleteRule: .nullify, inverse: \Approach.runway)
  public var approaches: [Approach]? = []

  /// Creates a runway with the given identifier.
  public init(identifier: String) {
    self.identifier = identifier
  }
}
