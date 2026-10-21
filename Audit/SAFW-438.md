# Safw 438 — implementation and validation record

The personal display name is **صفو** (Safw). The bundle identifier remains
`app.m1.mynoop.noop` so updating build 437 keeps the installed app's data.
Upstream is still the complete NOOP v12.0.0 source at
`9f98f811a6849ebcc333f51c0b37917f8d1f437e`. Original legal notices are unchanged.

## Localization and identity

- Reviewed 580 catalog entries across scoring guide, More, live sessions, customization,
  detailed timeline, metric explorer, devices, settings and breathing.
- Reviewed another 143 dependent entries, including breathing instructions and dynamic captions.
- Follow-up review added 491 daily-flow mappings and 344 health/workout mappings (some shared
  keys overlap). Main-app coverage is 2,524 / 4,292. The all-catalog figure also includes
  design/watch resources; neither count proves visual coverage or translation completeness.
- Fixed conditional Text/Label overloads that bypassed localization in sleep, stress, workout,
  comparison, backup and storage UI. Hydration weekday labels now use the active locale
  instead of taking the first letter of an English day. Repaired missing compiled keys for
  interpolated sleep-stage captions and imported hydration amounts.
- Added missing catalog keys, including keys in the design package's separate bundle.
- Fixed dynamic More headers, settings selectors, direction-bearing disclosure arrows,
  the detailed timeline day arrows, and letter spacing for connected Arabic text.
- The new original vector icon echoes the existing water vessels. A single Arabic wordmark
  replaces the individually spaced Latin letters. No score layout or water renderer redesign.
- Catalog coverage is 2,626 / 4,457 entries (58.92%), NOT 100% screen coverage. Many remaining flows,
  particularly advanced diagnostics, reports and secondary tools, still need translation.
  `Personal/localization-audit.json` is the exact generated inventory for each clean build.

## Stress access and research

- A permanent Today entry opens the existing stress screen even if custom cards are hidden.
- The main dial remains visible with a missing-data explanation when no score is available.
- Existing daily values show their actual scored day and are labelled as daily, not live.
- The existing NOOP score, sleep/recovery algorithms, BLE and packet decoder are retained.
- An opt-in minute research section adds a **different**, explicitly experimental HR-only
  candidate. It uses five minutes of recorded signal, reevaluated per completed minute.
- Only the active WHOOP 5 source's measured `hrSample` and `gravitySample` enter it.
  PPG-estimated HR, Apple values and imported daily metrics are not silently mixed in.
- HR coverage must be at least 80%, with no gap over 15 seconds, at least 30 samples in
  the final minute and a sample in its last ten seconds. Duplicate seconds do not count twice;
  conflicting duplicates are excluded. Missing motion (under 60% coverage) is not stillness.
- Motion masks activity and a 15-minute cooldown; known sleeps, naps, edited sleep onset
  and workouts are excluded. Undetected sleep remains a limitation, not a validated wake detector.
- Baseline references are real, nonoverlapping, earlier quiet windows, up to 14 days.
  At least six windows are required. The robust median/MAD HR transform is provisional;
  its logistic coefficients have NOT been fitted or validated against WHOOP.
- Wrist daytime HRV is intentionally omitted: upstream documented unreliable daytime RR
  artifacts. There is no claim this candidate matches WHOOP or measures psychological stress.
- Confidence is a conservative input-adequacy indicator, capped at 0.5, not a validated
  probability of accuracy. UI says low confidence rather than presenting false precision.
- The latest missing minute never carries a previous good score forward. Minute totals count
  unique one-minute intervals, not five-minute overlapping windows.

## Persistence and upstream divergence

`Modules/Analytics` and `Modules/Store` form an isolated `SafwResearch` Swift package
under `Personal/Research`. It depends on the existing upstream packages and GRDB and has
its own test suite. Only the private iPhone build mounts the feature. Android has no consumer of this optional research partition; upstream
canonical values and its schema version are unchanged.

An opt-in versioned, transactional migration (`personalSchemaMigration`, stress-minutes-v1)
creates `personalStressMinute` in the existing local SQLite database. Its key includes device,
time and algorithm version. Rows retain source, metric, unit, raw/derived distinction, feature
coverage, reason, baseline, confidence, batch ID, creation and update time. Upserts do not merge
other devices or versions. Device-data deletion clears this partition in the same transaction.
Full native database backups retain it; WHOOP CSV export does not include the research table.

Recording is driven by the existing repository refresh while the app is running. On opening,
stored raw history can reconstruct missed minutes for the current calendar day. It cannot
promise continuous background execution on iOS, and does not backfill every older day yet.
The history UI currently covers today; multi-day research navigation/comparison remains work.

## Accuracy work still required

WHOOP's own public description uses HR, HRV, motion and a 14-day personalized baseline;
it does not publish the formula or weights:
https://www.whoop.com/us/en/thelocker/introducing-stress-monitor-a-new-way-to-monitor-manage-stress/
(accessed 2026-10-08). This is a design reference, not ground truth or a validation dataset.

Next validation needs matched, timestamped observations across several ordinary days,
rest, walking, workouts, breathing and missing-signal periods; hold out days from calibration,
report error and coverage, and compare multiple subjects before making accuracy claims.
No personal screenshots or health exports are uploaded to CI. All new tests are synthetic.

## Validation status

- Overlay reapplies to a clean pinned checkout; catalog placeholder validation passes.
- Python overlay preservation checks pass. An initial full suite identified an upstream
  parity inventory conflict when personal-only research was placed in the shared core. The
  feature was moved into its own iPhone package with its own tests; no upstream parity gate
  or test was removed. Source-pattern and non-Arabic brand checks were also respected.
- 13 meaningful new analytics tests cover varying HR, absence, duplication, conflicts,
  holes, movement/cooldown, sleep/workout exclusions, baseline leakage, cold start,
  freshness, unique minute totals and ordering.
- 2 storage tests cover additive/idempotent migration, device/version isolation,
  transaction rollback, measured-only reads, timestamps and scoped deletion.
- Swift suites, real Release iOS build and iPhone 13 simulator screenshots must pass
  before calling build 438 verified. Hardware accuracy is not verified by a simulator.


## 2026-10-09 checkpoint

- Latest exact static inventory: 2,626 / 4,457 (58.92%); 106 uncatalogued occurrences,
  105 unique. Remaining untranslated catalog entries are explicitly listed in `localization.json`.
- All five original legal files are byte-identical to the pinned upstream copies.
- The full Tools Python suite passed 338 tests after the first follow-up translation batch.
  The final localization/research checkpoint also passed all 338 tests in 95.581 seconds.
  Subsequent widget/report brand-only edits passed the focused Home i18n checks and
  doc-comment lint. Exact results are recorded in `build-438.json`.
- New Swift research code was reviewed for module imports, declared test dependencies and
  source-switch races. It remains uncompiled because the Apple runner did not start.
- GitHub run 37849132860 failed before any job steps on 2026-10-08. One retry on
  2026-10-09 failed in the same way (Apple job 113794353302). No compiler output and no
  new IPA exist. The connector exposes no underlying annotation text; the cause is unknown.
  This is not evidence of a Swift compile failure or of successful compilation.
- The simulator harness is prepared to cover 42 captures, including empty stress, the opt-in
  research surface, breathing, each scoring-guide section, customization, Apple Health,
  storage, backup, hydration and HRV. The report records the actual build/name/commit.
  These new captures have NOT run. They are synthetic QA only, never user health data.
- Build 437 remains the last successfully produced IPA. It must not be relabelled as Safw 438.


## Billing gate identified (2026-10-09)

The owner supplied the Actions annotations for run 37925160762, source commit
`a086ad3cabcd8d05e9ad57ed699b67005d5a3288`. All four jobs were refused before
execution because recent account payments failed or the spending limit must be
increased. This establishes an account billing gate, not which of its two conditions
applies. No compiler or package test has run for 438.

The earlier unknown-cause notes above record what the connector exposed at that time.
The owner needs to check GitHub Billing and payments and Budgets and alerts. Do not
change payment details, raise spending, publish the private repository, or keep
retrying jobs as a workaround. Once the account block is resolved, resume the full
configured checks and simulator review, then package the real Release IPA. This
status-only documentation change deliberately skips CI; it does not mark any gate
as passed or change the app source.
