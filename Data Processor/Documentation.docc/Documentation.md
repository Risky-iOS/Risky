# Data Processor

A macOS tool that builds the airport database bundled with the Risky app.

## Overview

The Data Processor target downloads and combines four upstream sources, then
publishes a single LZMA-compressed property list to
[`Risky-iOS/Aviation-Data`](https://github.com/Risky-iOS/Aviation-Data) — at
`risky-data/<cycleName>.plist.lzma` on the `main` branch via the GitHub
Contents API — which the Risky iOS / macOS app downloads at runtime:

| Source                     | Provides                                  |
|----------------------------|-------------------------------------------|
| **FAA NASR**               | US airports, runways                      |
| **OurAirports** CSV        | International supplemental airports       |
| **FAA CIFP**               | Approach procedures                       |
| **R2-hosted SRTM tiles**   | Terrain for the mountainous-airport flag  |

The tool runs as either a SwiftUI macOS app (interactive) or a headless CLI
driven by environment variables (CI / scripted).

## Setup

1. Copy `Credentials.xcconfig.template` to `Credentials.xcconfig` (gitignored).
2. Fill in:
   - `RISKY_TERRAIN_PUBLIC_URL` — the public R2 URL where the SF50 TOLD
     tooling has uploaded its terrain region files.
   - `GITHUB_TOKEN`, `RISKY_GITHUB_OWNER`, `RISKY_GITHUB_REPO` — destination
     for the built airport plist.

## Headless mode

```sh
RISKY_HEADLESS=1 RISKY_NASR_CYCLE=current RISKY_SKIP_UPLOAD=1 \
  "/path/to/Data Processor.app/Contents/MacOS/Data Processor"
```

| Variable               | Values                                |
|------------------------|---------------------------------------|
| `RISKY_HEADLESS`       | `1` (required to enable headless)     |
| `RISKY_NASR_CYCLE`     | `current`, `next`, or `YYYY-MM-DD`    |
| `RISKY_SKIP_UPLOAD`    | `1` to write locally and skip GitHub  |

Output is written to `~/Library/Application Support/Risky Data Processor/`.

## Topics

### Pipeline

- ``NavDataProcessor``
- ``NASRProcessor``
- ``OurAirportsLoader``
- ``CIFPProcessor``
- ``AirportMerger``

### Terrain

- ``TerrainSampler``
- ``R2TerrainCatalog``
- ``SRTMRegionFile``

### Output models

- ``AirportDataCodable``
- ``AirportCodable``
- ``RunwayCodable``
- ``ApproachCodable``
