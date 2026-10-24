# Safw 440 — signal quality and measured glucose history

## Changes

- Minute stress research v2 rejects conflicting gravity/reference timestamps regardless of input
  order, requires recent continuous motion observations, and replays activity before a batch/day
  boundary to preserve the 15-minute cooldown. Movement can start cooldown even when HR is missing.
- Daytime research excludes both imported and locally computed sleep from the selected strap.
  Sleep must not train a daytime baseline. Existing v1 records remain separate and are not rewritten.
- Recovery refuses non-finite/invalid participating inputs and arithmetic overflow instead of letting
  a logistic clamp manufacture a score. Valid-input weights and formulas are unchanged. Its trace
  reports the same invalid-input gate. Comparison exports have a new calculation identifier.
- A new iOS screen reports measured 1 Hz HR coverage, conflicting seconds, and the longest missing
  run inside the latest recorded sleep block. It uses only the selected strap's measured HR table;
  imported scores and estimated PPG HR cannot fill missing samples. This is completeness, not accuracy.
- An optional read-only glucose view displays the previous seven days of Apple Health records with
  source, timestamp, manual-entry attribution, and mg/dL or mmol/L units. Apple Health performs unit
  conversion. Discrete chart points never interpolate gaps. No glucose/diabetes-risk inference,
  diagnosis, treatment advice, health writeback, or external glucose export is implemented.

## Glucose scope

Huawei describes the WATCH GT 7 Pro feature as a Diabetes Risk Study requiring 3–14 days of vital
sign tracking and the Huawei Research app. It explicitly does not replace diabetes diagnosis or
serve as a diabetes monitoring method. Its trained model and validation on WHOOP signals are not
available in this project. Safw therefore does not present a speculative diabetes-risk percentage.

Sources checked 2026-10-24:

- https://consumer.huawei.com/za/wearables/watch-gt7-pro/ (Diabetes Risk Study and footnote 24)
- https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bloodglucose
- https://developer.apple.com/documentation/healthkit/hkunit/moleunit(with:molarmass:)

The glucose connection asks for `.bloodGlucose` read access only after the user taps Connect.
Read authorization is private to HealthKit: empty results may mean no data or denied access. The
view never reports that read permission was granted. It refreshes on opening/foregrounding and
pull-to-refresh; it is not continuous monitoring, a notification service, or a treatment display.
Readings stay in view memory, and disconnecting clears them. A signed build must retain the
HealthKit entitlement; free sideload signing may strip it. An actual glucose device/app must already
be saving records to Health. No manual data entry is required by Safw.

## Platform and validation scope

This repository is the personal iOS build overlay. Research storage and new screens remain iOS-only.
The recovery hardening is applied to the shared Swift package with cross-platform regression tests;
the separate upstream Android app is not released by this overlay and is not represented as updated.
Bluetooth commands, decoders, persistent upstream schemas, and sleep-stage model weights are unchanged.

Synthetic regression cases cover gravity conflicts, stale motion, boundary cooldown, missing HR
during activity, conflicting baselines, incomplete/conflicting sleep signals, glucose provenance,
malformed history bounds, invalid recovery inputs and overflow, and valid formula preservation.
The normal workflow additionally builds both Apple targets and captures the new iPhone 13 screens
in normal and large text. Results are recorded separately after execution. A compilation/test pass
does not validate real strap physiology, HealthKit permissions, or glucose-device synchronization.
