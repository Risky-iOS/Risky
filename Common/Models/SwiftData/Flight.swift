import Foundation
import SwiftData

/// A planned or completed flight with its origin/destination, schedule, and risk answers.
@Model
public final class Flight {
  /// Date the flight record was created.
  public var createdAt = Date()
  /// Estimated time of departure (ETD).
  public var estimatedTimeOfDeparture = Date()

  private var _estimatedTimeEnrouteSeconds: Double = 0
  /// Estimated time enroute (ETE).
  public var estimatedTimeEnroute: Measurement<UnitDuration> {
    get { Measurement(value: _estimatedTimeEnrouteSeconds, unit: .seconds) }
    set { _estimatedTimeEnrouteSeconds = newValue.converted(to: .seconds).value }
  }

  /// Origin airport.
  @Relationship(deleteRule: .nullify)
  public var origin: Airport?
  /// Destination airport.
  @Relationship(deleteRule: .nullify)
  public var destination: Airport?

  /// Pilot in command.
  @Relationship(deleteRule: .nullify)
  public var pilot: Pilot?
  /// Aircraft used for the flight.
  @Relationship(deleteRule: .nullify)
  public var aircraft: Aircraft?

  /// Answers recorded for this flight’s questions.
  @Relationship(deleteRule: .cascade, inverse: \Answer.flight)
  public var answers: [Answer]? = []

  /// Creates a flight with the given origin/destination and schedule.
  public init(
    origin: Airport,
    destination: Airport,
    estimatedTimeOfDeparture: Date,
    estimatedTimeEnroute: Measurement<UnitDuration>
  ) {
    self.origin = origin
    self.destination = destination
    self.estimatedTimeOfDeparture = estimatedTimeOfDeparture
    self._estimatedTimeEnrouteSeconds = estimatedTimeEnroute.converted(to: .seconds).value
  }
}
