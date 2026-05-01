import Foundation
import SwiftData

/// An aircraft profile owned by the user. Holds aircraft-scoped questions and risk inputs.
@Model
public final class Aircraft {
  /// Tail number (registration) used to identify the aircraft.
  public var registration = ""
  /// ICAO type designator (e.g. "C172"), if known.
  public var typeDesignator: String?
  /// Date at which the aircraft profile was added.
  public var createdAt = Date()

  /// Whether the aircraft is equipped for IFR operations.
  public var IFREquipped = false
  /// Whether the aircraft is approved for flight into known icing.
  public var FIKI = false

  private var _minimumRunwayLengthMeters: Double?
  /// Pilot-set minimum runway length they are willing to use in this aircraft.
  public var minimumRunwayLength: Measurement<UnitLength>? {
    get { _minimumRunwayLengthMeters.map { Measurement(value: $0, unit: .meters) } }
    set { _minimumRunwayLengthMeters = newValue?.converted(to: .meters).value }
  }

  private var _cruiseSpeedMetersPerSecond: Double?
  /// Cruise speed used for ETE estimation.
  public var cruiseSpeed: Measurement<UnitSpeed>? {
    get { _cruiseSpeedMetersPerSecond.map { Measurement(value: $0, unit: .metersPerSecond) } }
    set { _cruiseSpeedMetersPerSecond = newValue?.converted(to: .metersPerSecond).value }
  }

  /// Aircraft-scoped questions seeded for this profile.
  @Relationship(deleteRule: .cascade, inverse: \Question._aircraft)
  public var questions: [Question]? = []

  /// Open squawks filed against this aircraft.
  @Relationship(deleteRule: .cascade, inverse: \Squawk.aircraft)
  public var squawks: [Squawk]? = []

  /// Flights logged in this aircraft.
  @Relationship(deleteRule: .nullify, inverse: \Flight.aircraft)
  public var flights: [Flight]? = []

  /// Creates an aircraft with the given registration.
  public init(registration: String) {
    self.registration = registration
  }
}
