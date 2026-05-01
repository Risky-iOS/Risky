import Foundation
import Logging
import RiskyCommon
import SwiftNASR

/// Downloads and parses an FAA NASR cycle into the Data Processor's internal
/// ``RawAirport`` form.
///
/// Adapted from the SF50 TOLD `DownloadNASR` implementation. Risky's airport
/// schema is simpler — no magnetic variation, no timezone, no glideslope,
/// no surface type, no reciprocal pairing — so the per-runway transformation
/// is a thin one.
struct NASRProcessor {
  /// Progress allocation within NASR processing (out of 100):
  /// - Download:        0..<22
  /// - Parse airports: 22..<98
  /// - Parse ILSes:    98..<100
  private static let downloadProgressEnd = 22
  private static let airportsProgressEnd = 98
  private static let ilsesProgressEnd = 100

  /// Minimum runway length in feet for a runway end to be retained.
  /// Mirrors SF50 TOLD's filter; rules out water and very-short surfaces.
  private static let minimumRunwayLengthFt = 500

  let logger: Logger

  func loadAirports(
    cycle: SwiftNASR.Cycle,
    onProgress: (@Sendable (Int, Int) async -> Void)? = nil
  ) async throws -> (airports: [RawAirport], cycle: CycleInfo) {
    await onProgress?(0, 100)

    let activeAt = cycle.effectiveDate ?? Date()
    guard let nasr = NASR.fromInternetToMemory(activeAt: activeAt) else {
      throw NASRError.unexpectedCycle(name: cycle.description)
    }

    logger.notice("Downloading NASR cycle \(cycle)…")
    do {
      try await nasr.load { progress in
        self.observeProgress(
          progress,
          mappingTo: 0..<Self.downloadProgressEnd,
          onProgress: onProgress
        )
      }
    } catch {
      throw NASRError.downloadFailed(underlying: error)
    }
    await onProgress?(Self.downloadProgressEnd, 100)
    try Task.checkCancellation()

    logger.notice("Parsing NASR airports…")
    do {
      try await nasr.parse(
        .airports,
        withProgress: { progress in
          self.observeProgress(
            progress,
            mappingTo: Self.downloadProgressEnd..<Self.airportsProgressEnd,
            onProgress: onProgress
          )
        },
        errorHandler: { error in
          self.logger.warning(
            "NASR airport parse error",
            metadata: [
              "error": "\(String(describing: error))"
            ]
          )
          return true
        }
      )
    } catch {
      throw NASRError.parseFailed(underlying: error)
    }
    await onProgress?(Self.airportsProgressEnd, 100)
    try Task.checkCancellation()

    logger.notice("Parsing NASR ILS records…")
    do {
      try await nasr.parse(
        .ILSes,
        withProgress: { progress in
          self.observeProgress(
            progress,
            mappingTo: Self.airportsProgressEnd..<Self.ilsesProgressEnd,
            onProgress: onProgress
          )
        },
        errorHandler: { error in
          self.logger.warning(
            "NASR ILS parse error",
            metadata: [
              "error": "\(String(describing: error))"
            ]
          )
          return true
        }
      )
    } catch {
      throw NASRError.parseFailed(underlying: error)
    }
    await onProgress?(Self.ilsesProgressEnd, 100)
    await NASRProgressObservations.shared.clearAll()

    let data = await nasr.data
    guard let airports = await data.airports else {
      return (airports: [], cycle: makeCycleInfo(from: cycle))
    }

    var raw = [RawAirport]()
    raw.reserveCapacity(airports.count)
    for airport in airports {
      if let mapped = makeRawAirport(from: airport) {
        raw.append(mapped)
      }
    }

    logger.notice("Parsed \(raw.count) NASR airports")
    return (airports: raw, cycle: makeCycleInfo(from: cycle))
  }

  private func makeRawAirport(from airport: SwiftNASR.Airport) -> RawAirport? {
    guard let elevationFt = airport.referencePoint.elevationFtMSL else { return nil }
    let identifier = airport.ICAOIdentifier ?? airport.LID
    guard !identifier.isEmpty else { return nil }

    var rawRunways = [RawRunway]()
    for runway in airport.runways {
      if runway.materials.contains(.water) { continue }
      guard let length = runway.length,
        length.converted(to: .feet).value >= Double(Self.minimumRunwayLengthFt)
      else { continue }

      if let baseEnd = makeRawRunway(from: runway, end: runway.baseEnd) {
        rawRunways.append(baseEnd)
      }
      if let reciprocalEnd = runway.reciprocalEnd,
        let mapped = makeRawRunway(from: runway, end: reciprocalEnd)
      {
        rawRunways.append(mapped)
      }
    }
    guard !rawRunways.isEmpty else { return nil }

    let latitude = airport.referencePoint.latitude.converted(to: .degrees).value
    let longitude = airport.referencePoint.longitude.converted(to: .degrees).value
    let elevationMeters = Double(elevationFt) * 0.3048
    let isLighted = rawRunways.contains(where: \.isLighted)

    return RawAirport(
      identifier: identifier,
      name: airport.name,
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
      isLighted: isLighted,
      mountainousTerrain: false,
      runways: rawRunways,
      approaches: [],
      source: .nasr
    )
  }

  private func makeRawRunway(
    from runway: SwiftNASR.Runway,
    end: SwiftNASR.RunwayEnd
  ) -> RawRunway? {
    guard let length = runway.length else { return nil }
    let lengthMeters = length.converted(to: .meters).value
    let TORAMeters =
      end.TORA?.converted(to: .meters).value ?? lengthMeters
    let TODAMeters =
      end.TODA?.converted(to: .meters).value ?? TORAMeters
    let LDAMeters =
      end.LDA?.converted(to: .meters).value ?? lengthMeters

    let isLighted = runway.edgeLightsIntensity != nil

    return RawRunway(
      identifier: end.id,
      isLighted: isLighted,
      lengthMeters: lengthMeters,
      TORAMeters: TORAMeters,
      TODAMeters: TODAMeters,
      LDAMeters: LDAMeters
    )
  }

  private func makeCycleInfo(from cycle: SwiftNASR.Cycle) -> CycleInfo {
    CycleInfo(
      name: cycle.description,
      effective: cycle.effectiveDate ?? Date.distantPast,
      expires: cycle.expirationDate ?? Date.distantFuture
    )
  }

  private func observeProgress(
    _ progress: Progress,
    mappingTo range: Range<Int>,
    onProgress: (@Sendable (Int, Int) async -> Void)?
  ) {
    guard let onProgress else { return }
    let span = range.upperBound - range.lowerBound
    let observation = progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
      let mapped = range.lowerBound + Int(Double(span) * progress.fractionCompleted)
      Task.detached { await onProgress(mapped, 100) }
    }
    Task { await NASRProgressObservations.shared.add(observation) }
  }
}

/// Holds KVO observations for SwiftNASR's internal `Progress` objects so they
/// stay alive long enough to fire callbacks. Cleared at the end of every NASR
/// run.
actor NASRProgressObservations {
  static let shared = NASRProgressObservations()

  private var observations: [NSKeyValueObservation] = []

  func add(_ observation: NSKeyValueObservation) {
    observations.append(observation)
  }

  func clearAll() {
    for observation in observations { observation.invalidate() }
    observations.removeAll()
  }
}
