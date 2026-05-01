# Risky

A flight risk assessment tool for Part-91 pilots. Risky helps pilots evaluate the risk of an upcoming flight by combining configurable, pilot-defined risk envelopes with live data pulled from many sources (airport, weather, terrain, NOTAMs, aircraft characteristics, etc.).

## ⚠️ Disclaimer

Risky is a decision-support tool. It does not replace pilot judgment, official data sources, or required preflight planning. Always cross-check critical information with authoritative sources before flight.

## Vision

Risky is inspired by the Flight Risk Assessment Tools (FRATs) used by Part-135 operators under their SMS programs (see AC 120-92D), but it is designed for **Part-91 pilots** who need something **fast, easy, and comprehensive without being preachy or prescriptive**.

A non-goal is reproducing the FAA's existing Part-91 [FRAT spreadsheet](https://explore.dot.gov/t/FAA/views/FRATTOOL/FRATTool?%3Aembed=y&%3Aiid=1&%3AisGuestRedirectFromVizportal=y). That tool is too rigid, too prescriptive, and as a result, almost no one uses it. Risky aims to be the opposite: a tool pilots reach for *because they want to*, that helps them define their own risk envelope and evaluate flights within it.

### Core design principles

- **Stoplight categorization, not scores.** Each risk factor is red / yellow / green. We do not produce a single numeric risk score; we produce a breakdown along PAVE categories (Pilot, Aircraft, enVironment, External pressures).
- **Pilot-configurable thresholds.** What is "yellow" for one pilot/aircraft combination is "red" for another. The pilot calibrates each stoplight to their own comfort and equipment.
- **Reduce numerical questions to categorical ones.** Where possible, replace "what is the density altitude?" with "is density altitude high?" If a numerical question can't be reduced to yes/no, fall back to bucketed thresholds.
- **Auto-fill, then ask.** When a flight is created, Risky answers as many questions as it can from data sources. The pilot fills in the rest, and can override any auto-filled answer.
- **Implicit experience tracking.** We do not capture pilot total time, IFR time, currency, etc. as separate inputs — those are implicit in how the pilot has configured their stoplights. As the pilot gains experience, they will naturally widen yellow/green bands.

## Features

### Profiles

- **Pilot profiles** — VFR/IFR ratings, IMSAFE-style risk tolerances (e.g., flying with a head cold), and any custom yes/no or tiered questions the pilot wants to track.
- **Aircraft profiles** — Equipment (VFR/IFR, FIKI, etc.), typical cruise speed, comfortable runway length, and any custom questions (e.g., "Starter motor acting up again?").
- Each risk factor on a profile is configured as a stoplight: yes/no questions map directly to red/yellow/green; multi-choice questions (e.g., flight category VFR/MVFR/IFR/LIFR) get a per-option stoplight; numerical questions are bucketed.
- A library of **standard custom questions** for each PAVE category is provided; pilots can adopt, modify, or delete them.

### Flights

- Origin, destination, ETD, and ETE (auto-calculated from aircraft cruise speed and route, editable).
- Risk is computed automatically on creation: each profile question is answered from data sources where possible; the pilot is prompted for anything that can't be auto-filled.
- Risk is presented as a **PAVE breakdown** (not a single score). Final UI TBD.
- Risk can be **recalculated** as departure approaches — automatically (e.g., when weather updates) or manually.

### Persistence & sync

- Profiles and flights are stored in **SwiftData** with **CloudKit** sync, so the same data is available across iOS and macOS.

## Future / shelved

- **Enroute weather** — Thunderstorms, icing, fuel freezing, turbulence, AIRMETs/SIGMETs/CWAs. Likely needs OpenMeteo subscription or direct GFS processing. Shelved until terminal-weather + core flow is solid.
- **Risk severity × likelihood matrix.** Some risks are rare-but-catastrophic; others are common-but-minor. A future version may weight risks along both axes rather than treating each stoplight as equal.
- **Mountainous overflight detection in-app.** The Data Processor flags mountainous airports at build time (see below); a future version of the Risky app could optionally download terrain data the same way SF50 TOLD does, and detect mountainous overflight along the route.

## Project structure

The Xcode project is a multi-target shell:

```
Risky/
├── Risky/                  # iOS + macOS app target (single target, multiplatform)
├── Common/                 # Shared framework — risk model, data layer, calculations
├── Data Processor/         # Standalone tool that produces the bundled airport database
├── iOS Widgets/            # iOS WidgetKit extension
├── macOS Widgets/          # macOS WidgetKit extension
├── CommonTests/            # Common framework unit tests
├── RiskyTests/             # App unit tests
├── RiskyUITests/           # App UI tests
├── Data ProcessorTests/    # Data Processor unit tests
└── Data ProcessorUITests/  # Data Processor UI tests
```

### Target responsibilities

- **Risky** — The user-facing iOS/macOS app. SwiftUI + SwiftData. Manages profiles, flights, and the risk-evaluation UI.
- **Common** — Framework linked into every other target. Houses the risk model (PAVE categories, stoplights, question schema), the data-source clients (weather, NOTAMs, etc.), and any logic shared between the app and widgets.
- **Data Processor** — A separate macOS tool (not shipped to end users). Downloads the latest FAA NASR cycle via SwiftNASR, downloads the prebuilt terrain rasters from the user's R2 bucket, and produces a processed airport plist with a `mountainousAirport` flag and any other precomputed fields the app needs. The output is uploaded as `risky-data/<cycleName>.plist.lzma` to [`Risky-iOS/Aviation-Data`](https://github.com/Risky-iOS/Aviation-Data); the Risky app fetches it at runtime, mirroring SF50 TOLD's `NavDataLoader` pattern. Modeled after SF50 TOLD's `DownloadNASR` target.
- **iOS Widgets / macOS Widgets** — Glanceable views of upcoming flight risk.

## Data sources

| Source                  | Library / service          | Used for                                                                                          |
| ----------------------- | -------------------------- | ------------------------------------------------------------------------------------------------- |
| Airport data            | SwiftNASR (via Data Processor) | Field elevation, runway lengths, available approaches, lighting, etc.                             |
| Terrain data            | EarthGIS rasters in R2     | Flag mountainous airports at processing time. Future: in-app download for overflight detection.   |
| Terminal weather        | WeatherKit + SwiftMETAR    | Composite ceiling, visibility, wind, precip at departure / destination.                           |
| Sun position            | Solar (ceeK/Solar)         | Civil-twilight-based night detection at departure/destination at ETD; daylight remaining at ETA. |
| Aircraft characteristics| SwiftACD                   | Cruise speed for ETE, approach category for minimums, etc.                                        |
| NOTAMs                  | Existing NOTAMs service (same as SF50 TOLD) | Critical NOTAMs at departure/destination, TFRs along route. Best-effort wheat-from-chaff filter.  |
| Enroute weather         | *(shelved)*                | Convective, icing, turbulence, fuel-freeze. Not in v1.                                            |
| EFB-planned flights     | *(import only)*            | Future: import flights planned in a third-party EFB rather than re-entering them in Risky.       |

All data-source clients live in **Common** so they can be shared by the app and widgets. The Data Processor uses SwiftNASR directly and embeds its terrain check at build time, not in the app.

## Development setup

### Prerequisites

- Xcode (with iOS/macOS SDKs supporting SwiftData + CloudKit + WeatherKit)
- WeatherKit entitlement on the developer account
- An R2 bucket (or comparable) hosting the terrain rasters consumed by Data Processor

### Dependencies

Managed via Swift Package Manager:

- **swift-algorithms**, **swift-async-algorithms**, **swift-collections**, **swift-numerics** — Apple standard utility packages
- **SwiftNASR** — FAA NASR parsing (used by Data Processor)
- **SwiftMETAR** — METAR/TAF parsing (used by Common)
- **SwiftACD** — Aircraft characteristics database (cruise speed, approach category, etc.)
- **Solar** ([ceeK/Solar](https://github.com/ceeK/Solar)) — Pure-Swift sunrise/sunset/twilight, USNO algorithm, no network
- **WeatherKit** — Apple framework, entitlement required

### Running

- The Risky app target is multiplatform (iOS + macOS).
- The Data Processor is a macOS tool run by the developer to refresh the bundled airport database; its output is committed (or pulled at build time) and shipped with the app.
