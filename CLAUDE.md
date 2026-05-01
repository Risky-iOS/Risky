# Implementation Decisions

This file captures specific, opinionated decisions about *how* Risky is implemented. The product vision and high-level architecture live in `README.md`.

## Risk model

### Stoplights, not scores

- Risk is **never** expressed as a single numeric score. Each risk factor produces a **red / yellow / green** stoplight, and the overall result is a **PAVE-category breakdown** (Pilot, Aircraft, enVironment, External pressures).
- Yes/no questions map directly to stoplights.
- Multi-choice questions (e.g., flight-category VFR/MVFR/IFR/LIFR) get a per-option stoplight assigned by the pilot in their profile.
- Numerical questions are first reduced to yes/no when possible (e.g., "high density altitude?"). When that's not possible, use a **bucket / tiered** representation rather than a continuous score.
- Stoplight thresholds are **per-profile**, not global. Identical environmental conditions can be green for one pilot/aircraft pair and red for another.

### PAVE-only categorization

- Every question (built-in or pilot-authored) belongs to exactly one PAVE category.
- The standard-question library is organized by PAVE category. Pilots can adopt, modify, or delete entries.
- Do **not** introduce a parallel categorization scheme.

### What we do *not* track

- Pilot total time, IFR time, currency, recency, etc. are **not** captured as separate inputs. They surface implicitly through how the pilot has calibrated their stoplights, and update naturally as the pilot widens green bands with experience.
- Do not add UI or schema for these unless the user explicitly asks.

### Auto-fill, then prompt

- When a flight is created, every question is answered from data sources where possible. The pilot reviews and can override any answer, then fills in the remaining manual ones.
- Manual / overridden answers persist on the flight; auto-filled answers should re-evaluate when their backing data changes (e.g., a fresh METAR triggers a recompute) — unless the pilot has overridden them.

### Future: severity × likelihood

- A 2D risk matrix (severity × likelihood) is on the roadmap but **not in v1**. Don't build for it speculatively; keep the question schema flexible enough to attach metadata later.

## Persistence

- **SwiftData + CloudKit** for profiles and flights.
- The Data Processor's airport database is downloaded at runtime from [`Risky-iOS/Aviation-Data`](https://github.com/Risky-iOS/Aviation-Data) (mirroring SF50 TOLD's `NavDataLoader`); cached on disk, not in SwiftData. Other small NASR-derived metadata bundled with the app lives in the bundle, not SwiftData.
- Use App Groups for sharing the SwiftData container with the widget extensions, the same way SF50 TOLD does.

## Data sources

- **Airport data** is processed offline by the **Data Processor** target into an LZMA-compressed plist published to [`Risky-iOS/Aviation-Data`](https://github.com/Risky-iOS/Aviation-Data); the Risky app downloads it at runtime. Follow `../SF50 TOLD/iOS/DownloadNASR` (publish side) and `../SF50 TOLD/iOS/SF50 TOLD/Loaders/NavDataLoader/NavDataLoader.swift` (consume side) closely as reference implementations.
- **Mountainous-airport flag** is computed by the Data Processor using terrain rasters fetched from the user's R2 bucket. The app does not download terrain in v1; that's a future expansion.
  - Use the FAA's **14 CFR Part 95 / Order 8260.3** definition: an area is "mountainous" when the **terrain elevation differential exceeds 3,000 ft within 10 NM**. Apply this to a window centered on each airport.
  - "Precipitous terrain" (FAA Order 8260.3 Appendix C) is a **distinct, additional** concept about adjacent rapidly-rising terrain that produces atmospheric effects. Do not conflate the two; if we ever flag precipitous terrain, it's a separate flag from mountainous.
- **Terminal weather** combines **SwiftMETAR** (live observations) and **WeatherKit** (forecasts) to produce a composite picture. Re-use the SF50 TOLD approach.
- **Sun position** uses **[ceeK/Solar](https://github.com/ceeK/Solar)** — pure Swift, no network, USNO algorithm, supports official/civil/nautical/astronomical twilight.
  - Use **civil twilight** as the night-determination cutoff, matching FAR 1.1's "night" definition (end of evening civil twilight to beginning of morning civil twilight).
  - Compute night/twilight at **departure airport at ETD** and **destination airport at ETA** independently — a daytime departure into a nighttime arrival is an important risk signal.
  - SunKit is a viable alternative if we later need azimuth/altitude (e.g., for sun-in-eyes risk). Don't add it speculatively.
- **Enroute weather** is shelved. Do not introduce GFS / OpenMeteo / AIRMET / SIGMET / CWA integrations until the user revisits this.
- **NOTAMs** use the same existing service as SF50 TOLD. The interesting work is filtering — best-effort to surface the critical few from the noisy many. TFRs deserve special handling.
- **Aircraft characteristics** come from **SwiftACD**. Used for ETE estimation (cruise speed) and approach category (minimums).
- **Heuristic / rule-of-thumb features are out of scope.** Every input either traces to a concrete data source or to an explicit pilot answer. No "this airport tends to be windy" / "DA tends to be high" features.

## Code style and conventions

The conventions below mirror SF50 TOLD, since that's the same author working in the same domain. Follow them unless this file says otherwise.

### Localization & strings

- All user-facing text uses `String(localized:)` unless passed directly to a SwiftUI view like `Text()`.
- Interpolate values using `FormatStyle`, e.g. `"Expires in \(days, format: .number) days."`
- Use curly quotes in user-facing strings.

### Formatting & linting

- Format with `swift format`; verify with `swiftlint`.
- Adhere to SwiftLint's `type_contents_order`:

```yaml
type_contents_order:
  order:
    [
      [type_alias, associated_type],
      [case],
      [type_property],
      [instance_property],
      [ib_inspectable],
      [ib_outlet],
      [initializer],
      [type_method],
      [view_life_cycle_method],
      [ib_action, ib_segue_action],
      [other_method],
      [subscript],
      [deinitializer],
      [subtype],
    ]
```

- Group related variables/constants with compound `let`/`var` syntax.
- When using `guard let` or `if let` to assert non-nil, **shadow** the variable name (use `if let foo`, not `if let bar = foo`, not `if let foo = foo`).

### Naming

- Capitalize all acronyms unless they conflict with a type name (e.g. `convertToKIAS`).
- Separate consecutive capitalized acronyms with an underscore (e.g. `IAS_KPH`). No underscore otherwise (`IASKts`, not `IAS_Kts`).
- Don't abbreviate words unless it clearly enhances readability. Long, clear names are fine.

### Documentation & comments

- Swift-DocC comments are only required on `public`/`package` types and members.
- Prefer small, well-named functions over comments to explain longer blocks.
- Don't write comments that describe history ("this used to be X; now it's Y"). Comments describe the code as it is.

### Code structure

- Complex functions are orchestrators; push detail into smaller helpers.
- No magic numbers. Use private static constants.
- For larger types, group related computed vars / functions / etc. into "functionality clusters" via extensions.

### Concurrency

- Swift 6 concurrency throughout. Use TaskGroups, actors, etc. as appropriate.
- Avoid `nonisolated(unsafe)` and `@unchecked Sendable` except when working with unavoidable pre-concurrency libraries (and prefer `@preconcurrency import` first).

### Units & measurements

- Use `Measurement` for front-end display and manipulation.
- For low-level calculations, primitives are fine. Suffix dimensional primitives/functions with abbreviated units (e.g. `timeMin`, `distanceNM`).

### SwiftUI

- Use icons sparingly — only when they enhance readability or as shorthand for a label. Unlabeled icons/images get an accessibility label.
- Use color sparingly — bright color only when it clearly enhances readability. Otherwise use shades for hierarchy. (Note: stoplights are an explicit, intentional exception — red/yellow/green is the *point*.)
- Prefer default padding/spacing unless visual flow demands otherwise.
- Always extract reusable view content into subview `struct`s — never use view-returning computed vars/functions or `@ViewBuilder` vars. Non-trivial subviews go in their own files; small ones may be `private struct`s in the same file.
- Prefer `Label` over `HStack { Image; Text }`.
- Every view has `#Preview` blocks covering its major modes; use a `PreviewHelper` to inject data.

### Testing

- Major functionality has unit tests; major user flows have UI tests.
- Unit tests use **Swift Testing**: `#expect` for assertions, `#require` for non-null.
- No trivial / tautological tests.

### Errors

- Each general error category gets its own protocol that inherits `Error`.
- Errors implement `LocalizedError`:
  - `errorDescription` is a general category description (often the same across cases, e.g. "Couldn't download file.")
  - `failureReason` carries case-specific detail with interpolated context (e.g. "Received HTTP error %lld when trying to download.")
  - `recoverySuggestion` only when the error is genuinely user-actionable.
- Use `fatalError` / `preconditionFailure` for invariants that must never break.

### Build output

- Run xcodebuild through **xcbeautify** to keep context lean.
- Parse Xcode output with **xclogparser** / **xcresultparser**.
