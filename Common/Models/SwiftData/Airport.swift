import CoreLocation
import Foundation
import SwiftData

/// A real-world airport sourced from the Data Processor’s navigation database.
@Model
public final class Airport {
  /// ICAO/FAA identifier (e.g. "KSFO").
  public var identifier = ""
  /// Human-readable airport name.
  public var name = ""
  /// Whether the airport sits in mountainous terrain per the FAA Part 95 / Order 8260.3 definition.
  public var mountainousTerrain = false
  /// Whether the airport has runway/taxiway lighting.
  public var isLighted = false

  private var _latitude: Double = 0
  private var _longitude: Double = 0
  /// Geographic location of the airport reference point.
  public var location: CLLocation {
    get { CLLocation(latitude: _latitude, longitude: _longitude) }
    set {
      _latitude = newValue.coordinate.latitude
      _longitude = newValue.coordinate.longitude
    }
  }

  private var _elevationMeters: Double = 0
  /// Field elevation above mean sea level.
  public var elevation: Measurement<UnitLength> {
    get { Measurement(value: _elevationMeters, unit: .meters) }
    set { _elevationMeters = newValue.converted(to: .meters).value }
  }

  /// Runways at this airport.
  @Relationship(deleteRule: .cascade, inverse: \Runway.airport)
  public var runways: [Runway]? = []

  /// Instrument approaches available at this airport.
  @Relationship(deleteRule: .cascade, inverse: \Approach.airport)
  public var approaches: [Approach]? = []

  /// Flights using this airport as origin.
  @Relationship(deleteRule: .nullify, inverse: \Flight.origin)
  public var originFlights: [Flight]? = []

  /// Flights using this airport as destination.
  @Relationship(deleteRule: .nullify, inverse: \Flight.destination)
  public var destinationFlights: [Flight]? = []

  /// Creates an airport with the given identifier and name.
  public init(identifier: String, name: String) {
    self.identifier = identifier
    self.name = name
  }
}
