# Public source preparation — 2026-10-21

## Publication boundary

The owner authorized public development to use standard public GitHub Actions runners.
A previous experiment branch in the existing private repository contains personal WHOOP CSV
exports and derived preview data. Making that entire repository public would expose those
branches and their history. Deleting the current CSV files alone would not remove history.

The publication candidate is a separate source-only snapshot of the NOOP-based personal overlay,
starting from `18fd175ab176aa3bc28343945eb7ab49ba49e448`. The 67 selected files were checked against
that tree, with the current changes documented below. No previous `.git` directory, branch,
health export, preview data, account secret, receiver state, build artifact or signing material
was imported. Original licensing and attribution files remain intact. The candidate needs a
new public repository initialized with a README; the existing private repository must not be
made public as a shortcut.

The connected GitHub tools can read and edit source but expose neither repository creation nor
visibility updates. The shell has no authenticated GitHub CLI. No browser session or alternative
credential was probed. Public repository creation is the remaining owner account action.

## Changes

- Build 439 preserves the existing bundle identity, water indicators and pinned upstream scorer.
- The receiver freezes the first per-device, per-version, per-sleep upload received one to 24 hours
  after the sleep ends, before reference fetching. It never replaces that primary prediction with
  a later revision. Late/backdated and legacy uploads stay diagnostic; missing or poor first
  predictions remain visible or excluded rather than being replaced with better revisions.
- The phone requires the matching report policy and shows the collection rule in Arabic.
- The main/public workflow includes source-boundary checks, Python tests, Swift packages,
  upstream macOS tests, the Release iOS build and an iPhone 13 simulator launch/screenshot job.
  The final gate requires every job. Private repositories cannot start the expensive jobs.
- The simulator harness includes the comparison screen at normal and large text sizes.
- The root ignore rules and tracked-source guard exclude known health exports, receiver state,
  credentials and build artifacts. This guard is narrow; it is not a guarantee that an arbitrary
  repository or history is safe to publish.

## Evidence and limitations

31 personal Python tests passed using synthetic fixtures, including the prospective snapshot,
late upload, missing prediction and revision checks. The overlay applied successfully to a clean
pinned checkout. Arabic format checks passed in all four catalogs, upstream doc-comment lint
passed, all tracked Python files compiled, workflow dependencies were checked, and the 68-file
tracked-source boundary and whitespace checks passed. Apple build, simulator execution, real OAuth,
strap behavior and physiological accuracy remain unverified for 439. No 439 IPA exists.

First-upload freezing prevents one retrospective replacement error; it does not make this a
blinded study or establish independent historical baselines. The report keeps both facts
explicitly unverified. Nightly stage totals measure agreement with WHOOP, not epoch-level or
clinical sleep-stage accuracy. No scoring coefficients or BLE behavior were changed, and no
automatic learning or continuous assistant access was added.

Once the new public repository exists and the source is uploaded to its main branch, its push
trigger can run the full build on standard hosted runners. Actual run results must be recorded
before describing the new app as built or tested.

## Publication and build outcome — 2026-10-21

The owner created the separate public repository [M1-0/safw](https://github.com/M1-0/safw).
Its source tree matched the reviewed 68-file snapshot exactly
(`da5c00ab1d04e8d03e415e71fc85d204bbf6ad6d`). Its source commit
`ff20035c20de6e703af5a5dbf3e8cdce9889e57a` has only the new repository's README commit as a parent;
the former private repository's history was not imported.

[Run 39654069505](https://github.com/M1-0/safw/actions/runs/39654069505) passed all six jobs, including the aggregate `verified` gate.
It produced a real build 439 IPA and 44 synthetic iPhone 13 simulator captures. The downloaded
IPA's SHA-256 matched its build manifest; app/widget build numbers, bundle identities, OAuth callback
scheme and permitted background identifier were checked in the packaged plists. The Today, Sleep,
normal comparison and large-text comparison captures were visually inspected.

Exact artifact and validation details are recorded in [build-439.json](build-439.json). The original
private repository remains private. Real WHOOP authorization, physical strap operation, independent
baselines and physiological accuracy remain untested. Publishing and compiling the code does not
establish sleep-stage or recovery accuracy.
