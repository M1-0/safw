# صفو · Safw

Build 441 focuses on signal integrity: delayed sleep/workout exclusions are rechecked across
minute-stress calibration history; uncalibrated or stale optional recovery baselines are omitted
from the score, driver rows and trace. The sleep-signal coverage screen remains, and the comparison
view now shows HRV/resting-HR differences and signed bias alongside recovery/stage totals.
The experimental glucose feature has been removed from this release. No diabetes-risk or glucose
inference is implemented. See [the 441 scope and validation protocol](Audit/SAFW-441.md).

Build 441 source `64b68aa96a43de5eda3b7997f61b5c3dd8867e5d` passed
[the complete public workflow](https://github.com/M1-0/safw/actions/runs/40677344405)
on its second attempt, including the final aggregate gate, actual Release IPA and 46 simulator
captures. See [the exact build evidence](Audit/build-441.json). Software tests do not establish
real physiological accuracy or superiority over WHOOP.

Build 439 prepares a clean public source snapshot and freezes the first timely nightly comparison.
The public source has no WHOOP exports or imported Git history. The combined workflow checks Python,
Swift packages, both Apple targets, and iPhone 13 simulator launches; it produces an unsigned IPA
only after the real Apple build succeeds. Build 439 passed the full public workflow on source
`ff20035c20de6e703af5a5dbf3e8cdce9889e57a`, producing a real unsigned IPA and 44 iPhone 13 simulator screen captures.
See [Audit/build-439.json](Audit/build-439.json) and [Audit/PUBLICATION.md](Audit/PUBLICATION.md).

Build 438 work is documented in [Audit/SAFW-438.md](Audit/SAFW-438.md). It preserves the installed bundle ID and the full upstream foundation. Build status is recorded separately; source changes are not proof of a successful IPA.

The optional [automatic personal comparison](Validation/README.md) collects local computed results
and compares them with the owner's official WHOOP reference without daily transcription. Its receiver
tests and Apple compilation pass in public CI; build 441 is available as an unsigned IPA. A real
WHOOP account connection and physical strap remain untested. It requires one-time receiver/TLS/OAuth
setup and explicit phone opt-in. The receiver
is user-owned; neither this repository nor the assistant provides an always-running hosted service.

# Personal iPhone build

Personal, noncommercial customization of the **complete ryanbr/noop source tree**, pinned to `9f98f811a6849ebcc333f51c0b37917f8d1f437e` (12.0.0 release line). iPhone 13 + WHOOP 5.0 are the intended test devices. The personal display name is صفو (Safw).

This branch is a reproducible **build overlay**, not another replacement implementation of NOOP. The workflow checks out the entire upstream repository at the pinned commit, applies these narrow customizations, runs upstream tests, and builds the actual `NOOPiOS` target. Protocols, SQLite, analytics, importers, and all existing features come from that checkout. No prebuilt upstream IPA is repackaged.

The capsule checks out pinned upstream source during the build rather than duplicating thousands
of unchanged files. Its clean publication snapshot deliberately excludes the previous private
repository's branches and Git history. A full local clone retains `upstream = https://github.com/ryanbr/noop.git`.

## Reproduce locally

Requires Python 3.12 + PyYAML 6.0.3. Building Apple apps additionally requires macOS, Xcode 26, and XcodeGen.

```bash
git clone https://github.com/ryanbr/noop.git noop
git -C noop remote rename origin upstream
git -C noop switch -c personal/mynoop-ar 9f98f811a6849ebcc333f51c0b37917f8d1f437e
python3 -m pip install PyYAML==6.0.3 -r Validation/requirements.txt
python3 apply.py noop
python3 -m unittest discover -s Tests -p 'test_*.py'
bash build.sh "$PWD/noop"
```

Run `apply.py` once on a clean checkout. It rejects a different upstream commit and changed source seams rather than silently guessing. `project.yml` is untouched; XcodeGen receives `project.personal.generated.yml`. Do not commit generated Xcode projects.

The output is `noop/build/personal-dist/Safw-12.0.0-441-unsigned.ipa`, **only after an actual successful Apple build**. The manifest records the upstream/customization commits and IPA SHA-256. SideStore supplies device signing. The app uses `app.m1.mynoop.noop`; the widget uses `app.m1.mynoop.noop.widgets`. Both use the independent personal App Group. The upstream sideload preparation script preserves HealthKit and widget entitlement requests. Watch embedding is stripped in line with upstream sideload releases.

## Implemented customizations

- Arabic is seeded before SwiftUI initializes app/bundle state. An explicit language choice survives updates. English remains the source catalog language, and existing locales are preserved.
- Four existing String Catalogs receive Arabic entries through byte-local JSON edits. `ar.json` is the reviewed source; `ar.tsv` records the phrase map. Brand names and technical acronyms are intentionally retained where clearer.
- Locale and layout direction are explicit. Today/day/tab swipe direction is normalized; semantic forward/backward icons replace physical navigation chevrons in the main surfaces. Arabic Today headings omit Latin letter spacing.
- The upstream Today dashboard is retained. Build 437 restores the water vessel renderer from upstream commit `4667cb3` in an isolated personal component; current upstream uses rings. It reuses current LiquidSim, motion policy and score values, honors reduced motion/background state and keeps navigation taps working. The personal Stress view uses upstream's open `BevelGauge` with the existing daily score. Build 438 pins its entry on Today and adds an isolated, opt-in minute research surface; it does not replace the daily algorithm. See the 438 record for its signal gates and limitations.
- New installs disable the optional update check and Coach entry until enabled by the user. Existing choices are preserved. No telemetry or automatic experimental BLE commands are added. The new personal comparison lane is off by default and exports only to the owner-configured receiver after explicit opt-in; it never writes reference scores into the normal analytics store.
- Original LICENSE, NOTICE, ATTRIBUTION, DISCLAIMER and TERMS are preserved and included in the app; resolved dependency notices are bundled before signing.
- One conditional FoundationXML import fixes a real Linux compilation failure in `XlsxSheet.swift`. Parsing behavior is unchanged.
- A regression test covers waking at Fajr for 2 or 25 minutes and returning to sleep. It checks grouping/accounting, not sensor-based detection on a real person.

## Update from upstream

Keep the original remote. Fetch and review a selected release in a separate worktree, compare LICENSE/NOTICE/ATTRIBUTION, rebase the small source changes, then update `config.json` and the workflow's pinned SHA together. Re-run catalog extraction, placeholder checks, all package/app tests, and device checks. Lower the Arabic missing-string allowance as translations land. Do not rewrite the upstream core to avoid a merge conflict.

## Status and acceptance

Build 441 passed [public CI run 40677344405](https://github.com/M1-0/safw/actions/runs/40677344405)
on source `64b68aa96a43de5eda3b7997f61b5c3dd8867e5d`: 31 personal Python tests, 338 upstream
Tools tests, 234 capture-tool tests (one skipped), 4430 Swift-package tests (two skipped), and
2267 macOS app tests (two skipped), with no test failures. Runtime/language checks, the synthetic
import round trip, Release iOS packaging, simulator job and final aggregate gate passed. The
37 targeted signal/recovery regression tests are included in these suites, not additional tests.

The first simulator attempt reached its 45-minute job limit during diagnostic collection after
all 46 captures. Rerunning that job on the same source completed successfully; no source change
or reduced test scope was needed. The other successful jobs and the IPA came from attempt one.

The iPhone 13 simulator used iOS 26.5, retained Arabic defaults and captured 46 screens after
checking each launch survived eight seconds, using empty or synthetic data. Eight representative
captures from the first attempt were visually reviewed, including normal/large signal coverage
and comparison settings. This is not an interaction test of every screen, a complete Arabic
rollout, a visual test of populated comparison results, real OAuth validation, hardware validation
or physiological accuracy evidence. The audit records the exact IPA hash and verification scope.

The IPA has the existing personal bundle id and a new build number. SideStore signs it for the
owner's phone. Comparison remains disabled until its receiver and WHOOP authorization are
configured. Historical build 436–438 evidence remains in the dated audit files.

After installing a successfully built IPA: verify opening, Arabic/RTL, Bluetooth permission, WHOOP 5 scan/connect/HR/battery, reconnection after locking, ZIP import and repeated import, restart persistence, HealthKit read consent, and a night interrupted at Fajr. Compare days/sources against WHOOP without treating WHOOP as ground truth. Do not install over the existing upstream or official app; verify the separate bundle identity first.
