# صفو · Safw

Build 439 prepares a clean public source snapshot and freezes the first timely nightly comparison.
The public source has no WHOOP exports or imported Git history. The combined workflow checks Python,
Swift packages, both Apple targets, and iPhone 13 simulator launches; it produces an unsigned IPA
only after the real Apple build succeeds. Public publication and the 439 Apple build are pending.
See [Audit/PUBLICATION.md](Audit/PUBLICATION.md) for the exact verification boundary.

Build 438 work is documented in [Audit/SAFW-438.md](Audit/SAFW-438.md). It preserves the installed bundle ID and the full upstream foundation. Build status is recorded separately; source changes are not proof of a successful IPA.

The optional [automatic personal comparison](Validation/README.md) collects local computed results
and compares them with the owner's official WHOOP reference without daily transcription. Its receiver
tests pass locally; its new Apple code has not been compiled, authorized with an account, or shipped
as an IPA. It requires one-time receiver/TLS/OAuth setup and explicit phone opt-in. The receiver
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

The output is `noop/build/personal-dist/Safw-12.0.0-439-unsigned.ipa`, **only after an actual successful Apple build**. The manifest records the upstream/customization commits and IPA SHA-256. SideStore supplies device signing. The app uses `app.m1.mynoop.noop`; the widget uses `app.m1.mynoop.noop.widgets`. Both use the independent personal App Group. The upstream sideload preparation script preserves HealthKit and widget entitlement requests. Watch embedding is stripped in line with upstream sideload releases.

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

See `Audit/SAFW-438.md` for the current checkpoint and `Audit/REPORT.md` for historical validation. Build 438 source is saved, but its CI jobs failed before any steps; no 438 IPA has been built. This checkpoint is **not a claim of a fully Arabic or daily-use-validated app**. Build 436 passed the full configured Apple/package/Python gates and produced an IPA. Build 437 also produced a real Release IPA, but the protocol rerun jobs and new simulator job did not start; the aggregate 437 gate is not green. See the audit for the exact evidence boundary. Its iPhone 13 simulator audit captured 19 screens; those images revealed the ring appearance, a reversed NOOP wordmark and clipped Arabic units, addressed in build 437. No physical strap or HealthKit authorization test has been performed. A green package suite is not an iOS app build. The GitHub Actions `verified` job requires every configured job to pass; an IPA artifact alone is not that gate.

After installing a successfully built IPA: verify opening, Arabic/RTL, Bluetooth permission, WHOOP 5 scan/connect/HR/battery, reconnection after locking, ZIP import and repeated import, restart persistence, HealthKit read consent, and a night interrupted at Fajr. Compare days/sources against WHOOP without treating WHOOP as ground truth. Do not install over the existing upstream or official app; verify the separate bundle identity first.
