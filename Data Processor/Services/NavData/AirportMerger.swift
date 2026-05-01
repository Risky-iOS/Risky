import Foundation
import Logging

/// Merges NASR + OurAirports + CIFP results into a single normalized
/// `[RawAirport]` ready for terrain sampling and final encoding.
///
/// Rules:
/// - **Identifier conflicts**: NASR wins over OurAirports. NASR's coverage of
///   the US is authoritative; OurAirports is only there to fill in airports
///   NASR doesn't list (typically international).
/// - **Approaches**: CIFP entries are attached at the airport level. Each
///   approach carries an optional runway identifier — circling approaches
///   leave it `nil`. An airport with no NASR or OurAirports entry but only
///   a CIFP listing is dropped — we have no runway/elevation/location info
///   for it.
struct AirportMerger {
  let logger: Logger

  func merge(
    nasr: [RawAirport],
    ourAirports: [RawAirport],
    approaches: ApproachLookup
  ) -> [RawAirport] {
    var byIdentifier: [String: RawAirport] = [:]

    for airport in nasr {
      byIdentifier[airport.identifier] = airport
    }

    var supplementalCount = 0
    for airport in ourAirports where byIdentifier[airport.identifier] == nil {
      byIdentifier[airport.identifier] = airport
      supplementalCount += 1
    }

    if supplementalCount > 0 {
      logger.notice(
        "OurAirports contributed \(supplementalCount) supplemental airports"
      )
    }

    var attachedApproachCount = 0
    for identifier in byIdentifier.keys {
      guard let approachList = approaches.byICAO[identifier],
        var airport = byIdentifier[identifier]
      else { continue }

      airport.approaches = approachList
      attachedApproachCount += approachList.count
      byIdentifier[identifier] = airport
    }

    logger.notice("Attached \(attachedApproachCount) CIFP approaches")

    return byIdentifier.values.sorted { $0.identifier < $1.identifier }
  }
}
