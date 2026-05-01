# TODO / Open Questions

Items raised during early planning that need a decision but didn't belong in `README.md` or `CLAUDE.md`.

## Additional data sources — decisions made

Original brainstorm with the user's decisions applied:

- **Sun / civil twilight** — ✅ **In scope.** Use [ceeK/Solar](https://github.com/ceeK/Solar) (pure Swift, USNO algorithm, no network, civil/nautical/astronomical twilight built in). Determine night and twilight automatically at departure (at ETD) and destination (at ETA). See CLAUDE.md for the night-definition decision.
- **PIREPs** — Defer with the rest of enroute weather. Revisit when enroute is unshelved.
- **GPS / GNSS outage NOTAMs** — Likely worth a dedicated bucket inside the NOTAM filter. Revisit during NOTAM-pipeline implementation.
- **Solar / space weather (Kp index)** — Niche; defer.
- **TFRs along route** — In scope as part of NOTAM handling; needs a route-buffer query, not just endpoints. Track during NOTAM-pipeline implementation.
- **ADS-B / surveillance coverage gaps** — Defer.
- **Fatigue** — ✅ **In scope, reframed.** Don't model duty time (Part-91 has no such concept; Part-117/Part-135 limits don't apply). Frame as a self-assessed **"long flying day"** question with looser, pilot-configurable thresholds. Lives in the Pilot bucket. Likely a candidate for a built-in standard custom question rather than a hard-wired data source.
- **Calendar integration** — ❌ **Out of scope.**
- **EFB integration** — ✅ **Scoped down to import only.** Future: import EFB-planned flights into Risky so the pilot doesn't re-enter origin/destination/ETD/route. No outbound sync, no two-way binding. Specific EFB(s) TBD.
- **"DA tends to be high" / airport-reputation heuristics** — ❌ **Out of scope.** This app is data-driven, not vibe-driven. (See `feedback_data_not_vibes` memory.)

## Pending design TBDs flagged in README

These remain TBD; pulled here so they're easy to track:

- Final visual design of the **PAVE breakdown** result screen.
- Final UX for **manual recalculation** as ETD approaches (notification cadence, what auto-triggers a recompute).
- Schema shape for keeping the question model **flexible enough to add severity × likelihood later** without a migration.
- **Mountainous-airport algorithm parameters** — The FAA definition (terrain differential > 3,000 ft within 10 NM, per 14 CFR Part 95 / FAA Order 8260.3) is now adopted in CLAUDE.md. Implementation specifics still TBD: window shape (square vs. circular), grid resolution from the EarthGIS rasters, exact differential metric (max−min vs. percentile-based to suppress outliers).
- **EFB import format(s)** — which EFB apps to support, and what import path (file picker, share sheet, URL scheme).

## Project housekeeping

*(no outstanding housekeeping items — SwiftACD and Solar are now linked into the project)*
