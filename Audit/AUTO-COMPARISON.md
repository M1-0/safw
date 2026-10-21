# Automatic comparison checkpoint — 2026-10-17

## Request and resulting behavior

The owner wants to install Safw and avoid daily transcription or screenshot comparison with WHOOP.
The personal overlay now contains an optional iPhone collector, a server-side WHOOP OAuth receiver,
and an Arabic comparison page linked from Today and Data Sources. Details and setup are in
[`Validation/README.md`](../Validation/README.md).

The receiver uses the owner's official read-only recovery and sleep permissions plus refresh access.
The phone exports computed results only after configuring the owner endpoint and enabling comparison.
The app never receives the WHOOP client secret or upstream access/refresh tokens. The receiver keeps
encrypted records and compares nightly totals and recovery measurements in separate algorithm/device
groups. It does not import official scores back into the app's computation or silently train a model.

The workflow requests best-effort background refresh and catches up on foreground/data refresh.
iOS may deny or defer background execution. A running, reachable owner receiver is necessary.
The assistant has no standing access to the phone or receiver and does not work continuously in
the background merely because this code exists.

## Verification completed locally

- 25 personal Python tests passed, including 22 receiver/comparison tests and 3 existing overlay tests.
- 338 upstream Tools Python tests passed on a clean pinned checkout with the overlay applied.
- Full overlay application succeeded on upstream `9f98f811a6849ebcc333f51c0b37917f8d1f437e`.
- Source whitespace checks, upstream detached-doc-comment lint, generated URL callback and background
  identifier checks passed. New UI copy has Arabic catalog entries and matching format placeholders.
- Synthetic fixtures only; no real WHOOP credentials or user health records were used or uploaded.

## Required before delivery as an installable feature

- Xcode compile and simulator/device layout checks: **not run**. No Swift toolchain or macOS runner
  is available in this workspace; the existing Actions billing/quota block was not retried.
- No new IPA was generated. Build 437 remains the last known built IPA from the earlier work.
- No WHOOP developer application, callback host, TLS receiver, login grant, secret or billing setting
  was created or changed. These require one-time owner account/environment access.
- OAuth/browser/background/Keychain behavior and a real strap night remain untested.
- The existing recovery algorithm's historical baseline independence is not certified by source
  namespace checks. The report explicitly marks that as unverified.
- Nightly stage-minute agreement is not stage-by-stage accuracy; the official API does not provide
  a full hypnogram. No clinical accuracy, WHOOP parity or automatic model improvement is claimed.

The change is confined to the personal iPhone fork. It preserves upstream licensing, storage,
scoring, BLE behavior, the water indicators and existing bundle identity. No hosted service or
automatic paid build is activated. Source persistence uses a separate experimental private branch.
