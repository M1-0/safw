# NOOP architecture and personal milestone audit

Pinned upstream: `ryanbr/noop`, commit `9f98f811a6849ebcc333f51c0b37917f8d1f437e`, 12.0.0 release line. Latest release was verified as v12.0.0 on 2026-10-07. This is a source/test audit, not a complete visual audit of every screen and not a hardware certification.

## License and attribution

LICENSE (PolyForm Noncommercial 1.0.0), NOTICE and ATTRIBUTION were read before implementation. All are retained verbatim, with DISCLAIMER and TERMS. The required notice is `Copyright 2026 NoopApp`. GRDB.swift and ZIPFoundation retain their MIT notices; MarkdownUI and transitive dependency licenses are also collected from the resolved source checkouts. NOTICE describes protocol facts-only reuse while ATTRIBUTION describes earlier Swift packages/collection logic as adapted; that wording difference is retained rather than silently rewritten. No legal clearance beyond the actual supplied license is asserted.

## Architecture

| Layer | Source | Assessment |
|---|---|---|
| Protocol | Packages/WhoopProtocol | Pure frame/CRC/command/packet decoding; WHOOP 4/5 family handling; no CoreBluetooth |
| Radio and collection | Strand/BLE, Strand/Collect | Shared Apple BLE connection, live streams, historical offload, raw logging; requires real-device testing |
| Storage | Packages/WhoopStore | GRDB SQLite, WAL pools, migrations, per-device stream/cache tables; no replacement database introduced |
| Analytics | Packages/StrandAnalytics | Recovery, effort, HRV, sleep V1/V2, stitching, stress, correlations and related math retained |
| Import | Packages/StrandImport + Strand/Data/WhoopImporter.swift | ZIP/CSV and streaming Apple Health XML parsing, then app-to-store mapping |
| Shared app | Strand/Data, Screens, Liquid, App | Repository, source arbitration, derived metrics, shared UI |
| iPhone | StrandiOS, StrandiOSShared, StrandiOSWidgets | NOOPiOS target, tab navigation, HealthKit, widget/Live Activity snapshots; iOS 17+ |
| Other Apple | NOOPWatch, NOOPWatchComplications; Strand macOS target | Retained source; macOS-only integrations should remain platform-specific |
| Design | Packages/StrandDesign | Shared SwiftUI tokens/components, including the liquid gauges and open dial |
| Research | Tools/SleepBench, SleepPSG | Retained; no new PSG model or replacement for SleepStager V2 |

Upstream has the requested dashboard, Live/Breathe/Intervals, Sleep, Trends, Workouts, Health, Stress, insights, source/import/export settings and diagnostics. Availability and interaction vary by platform; app compile/device testing is needed before claiming every feature works on iPhone.

## WHOOP 5 support and evidence boundaries

- Upstream documents hardware-confirmed live HR. Battery, R-R, historical sync, packet decoding and raw/deep logging paths exist. This environment has not connected to the user's strap.
- WHOOP 5 R-R handling includes firmware/capture-supported millisecond interpretation, separate channels and guards against ambiguous legacy units. Historical completeness remains dependent on firmware and uninterrupted collection.
- R22 configuration, R26/v26 optical decoding and PPG/raw persistence already exist. Deeper WHOOP 5/MG channels remain experimental and are not enabled automatically by this overlay.
- Candidate SpO2 bytes and offline PPG-derived readings are not validated substitutes for measured oxygen saturation. Motion, temperature and respiratory interpretations have hardware/signal limitations. Experimental candidates must stay in diagnostics.
- Sleep stages and recovery/effort are NOOP estimates. WHOOP official outputs are comparators, not ground truth.

## Imports: tested behavior and remaining gaps

The user's WHOOP ZIP was run through the **actual app WhoopImporter** linked to the real StrandImport and WhoopStore libraries in a temporary SQLite store. Observed result on 2026-10-07:

| Category | Parsed | Persisted |
|---|---:|---:|
| Cycles / daily rows | 23 | 22 |
| Sleeps | 22 | 22 |
| Workouts | 2 | 2 |
| Journal answers | 45 | 45 |

Two cycles map to the same wake day. Reimport left counts unchanged; a sentinel record under another source remained intact; strain 0–21 to 0–100 and sleep-efficiency percent to fraction matched the app's ordered-upsert contract. No parser spans were skipped. No naps were present in this file. The test does **not** establish lossless archival of all raw CSV rows: the daily table intentionally has one row per source/day.

The app mapping currently excludes imported naps from its sleep-session loop. WHOOP absolute skin temperature is assigned to the deviation-named field, which needs a deliberate mapping correction and regression tests. Imported history is displayed; complete use of that history for every NOOP calibration/baseline pathway still needs verification. Original user files are not included in this repository or CI.

## HealthKit and provenance

The iOS bridge is real: HealthKit entitlements, authorization, anchored/observer queries, workouts/sleep, quantity queries and opt-in writeback are present. HR, RHR, SDNN HRV, respiration, oxygen, activity/energy, steps, weight and VO2-related types are represented. Type availability is not proof that a given Apple Watch model has measurements.

Gaps: direct wrist-temperature reading is not in the current read list; XML import can parse the corresponding export type. Read/write authorization requests need separation for minimal permissions. Daily aggregations use a shared Apple Health source and do not retain every sourceRevision identifier/sample UUID. Multiple sleep sources need interval-overlap review. XML app import uses bounded-memory aggregation with raw-sample retention disabled. These paths do not yet meet the user's full sample-level provenance requirement.

The desired additive measurement model should keep timestamp, metric, value/unit, device/source identifiers, raw/derived kind, algorithm version, coverage/confidence, import session and creation time. Canonical display/fusion must remain a separate view over preserved source measurements. No speculative migration was added in the build/localization milestone.

## Fusion, cold start and stress

Existing FusionResolver/MetricArbitrationPolicy select deterministic per-metric/day winners and report contributors/conflicts. They are not a sample-level gap-filling engine. WHOOP-import priority and Apple HRV SDNN versus WHOOP RMSSD require explicit semantic review. Steps must not be summed across overlapping devices; overlapping sleeps must not be counted twice.

The current stress timeline scores **hour-long windows every 30 minutes**, with waking-hours limits of 06:00–22:00. The daily/import stress estimate is not a minute-by-minute official WHOOP series. Neither this overlay nor the WHOOP CSV file supplies the requested 24-hour minute history. A future minute record must retain window, coverage, source, algorithm version and unavailable/activity-masked reasons; repeating hourly values into minutes would be misleading. The new dial is presentation only.

Recovery currently has seed-night gates and confidence tiers. No arbitrary population percentage was inserted. Future preliminary estimates need genuine inputs, value/confidence/calibration/reasons, and a distinct insufficient-signal state. The proposed Fajr regression exercises the existing grouping/awake accounting without changing the sleep detector.

## Localization and RTL

The four Apple catalogs contain 4,384 keys, of which 4,278 are marked translatable, including one newly catalogued upstream key. Build 437 currently has 952 Arabic catalog entries (22.25%), up from 561 (13.12%) in build 436. These are catalog-entry counts, not unique visible phrases or fully translated screens. The personal generated inventory is authoritative. It also found 239 uncatalogued candidate occurrences (224 distinct strings); these are static scanner candidates, not a complete census of visible text.

Arabic catalog infrastructure, startup language, localized permission strings, core navigation gestures/icons and Today heading spacing are implemented. Brands and technical acronyms intentionally retain their accepted names. Numeric templates use BiDi isolation where needed. Full Arabic plural grammar, context-specific uses of shared keys, units/date labels, charts, all screens, large text, VoiceOver, dialogs, widget language synchronization and chart time direction remain to be checked on an Apple build. English fallbacks remain and are not mislabeled as translated.

## Durable build and test evidence

Build 436, customization `1fdf745f15cb8064700714eb813bc3eed552add9`, passed all configured gates in [run 37581186799](https://github.com/M1-0/whoop-lab/actions/runs/37581186799):

| Suite | Observed result |
|---|---|
| WhoopProtocol / OuraProtocol / PolarProtocol | 812 (1 skipped) / 267 / 25 tests, no failures |
| WhoopStore / StrandImport | 632 / 327 (1 skipped), no failures |
| StrandAnalytics / StrandDesign / NoopLocalAccess | 2,136 / 134 / 14 tests, no failures |
| SleepBench / SleepPSG | 13 / 33 tests, no failures |
| Backfill | Built; no test target |
| macOS shared app | Built and 2,267 tests (2 skipped), no failures |
| Python tools / Linux capture | 338 / 234 (1 skipped), no failures |
| Personal checks | 3 Python checks; runtime defaults/language/RTL; actual importer + SQLite synthetic round trip passed |
| iOS Release | NOOPiOS built and packaged; bundle identities, compiled Arabic, legal files and entitlements checked |

The first attempt surfaced a missing Arabic step-chart translation gate and a test that confused inherited AppleLanguages with a local UserDefaults override. Both were corrected; no upstream checks were removed.

Build 436 IPA: 23,961,800 bytes, SHA-256 `ed6ccd83fcdf81ad08d79363cb3b26f10ace360cc29a7028dc528176c215f2be`. This is the real app, built from source, with SideStore signing still required.

Unchanged upstream Android assembled and passed in [run 37582743703](https://github.com/M1-0/whoop-lab/actions/runs/37582743703). Downloaded JUnit XML totals: 779 suites, 6,637 tests, zero failures/errors, 6 skipped. This is baseline retention evidence; no Arabic Android fork is claimed.

An actual iPhone 13 simulator on iOS 26.5 built, installed, launched and captured 19 screenshots in [run 37612307022](https://github.com/M1-0/whoop-lab/actions/runs/37612307022). Each captured screen stayed alive for eight seconds; three also used XXXL text. The first launch persisted Arabic. Fixtures were synthetic and limited to the Debug simulator. Screenshots prove rendering/launch, not every interaction or device reliability. An earlier simulator run built but failed to launch; using Xcode simulator signing instead of the device SideStore preparation resolved the next run.

## Build 437 customization and remaining visual work

- Arabic first-run terms, onboarding/import copy, live connection controls, Today actions and stress explanations. Existing Latin brands and useful technical acronyms stay intact.
- Water spheres reuse NOOP's original renderer from `4667cb3dab02bd8ed990b09821bbbb6a6db94029`, isolated in PersonalWaterVessel; current LiquidSim and reduced-motion/power policies remain. No physiology or stored value changed.
- The NOOP letter row is explicitly LTR inside the RTL interface. Onboarding arrows use semantic directions. The stress clock ruler stays aligned with its chronological Canvas.
- Stress marker units and baseline comparisons use separate lines to avoid the clipping observed on build 436.
- All original ring rendering tests and algorithm/import/store suites are retained. The personal renderer applies only to iOS; Android/macOS calculations and source remain unchanged.

Build 437 Apple compilation and simulator review are pending at this source checkpoint. Full-screen Arabic coverage, chart direction/scrubbing, large text, VoiceOver and interactive onboarding/permission/import flows remain incomplete. English fallback text is still visible in many secondary screens. The minute-by-minute stress store and import/provenance fixes are separate milestones.

## Device acceptance for the first actual IPA

1. Install beside official WHOOP and upstream NOOP; verify the distinct app name and ID.
2. Check Arabic startup, three liquid spheres, dial, all main tabs and RTL day swipes at normal/large text sizes.
3. Grant Bluetooth access and connect WHOOP 5. Check live HR, battery, background/reconnect and a historical offload. Do not enable unfamiliar raw probes for the first connection test.
4. Import the original WHOOP ZIP, verify 22 daily rows/22 sleeps/2 workouts and repeat import; restart and verify persistence.
5. Grant only the desired Apple Health reading permissions. Compare source identifiers and gaps; do not assume all Watch sensors exist.
6. Record a full night, including Fajr interruption; compare start/end, sleep/awake totals and confidence to the official app as a comparator.
7. Export a NOOP backup before replacing builds. Minute-level stress history and full provenance are subsequent milestones, not completed claims.
