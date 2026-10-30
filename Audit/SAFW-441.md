# Safw 441: current classifications and usable baselines

## Resulting behavior

- Stress research v3 rechecks each historical five-minute calibration window against current
  sleep/workout exclusions. A delayed sleep classification can no longer keep that window in the
  daytime reference pool. The query covers the full 14-day history, both selected-strap sleep
  namespaces, corrected start times, and sleeps overlapping the lower boundary. It does not
  truncate exclusions at 100 rows. Same-minute repository updates invalidate the refresh key.
- Minute analysis rejects malformed/unbounded time ranges before arithmetic or iteration.
  Existing v1/v2 research records remain stored separately. No recorded physiological data is deleted.
- Recovery omits uncalibrated/stale respiration and prior-effort baselines, matching the existing
  resting-HR rule. Respiration driver rows and trace apply the same gate. All usable-baseline weights
  and formula constants remain unchanged. Invalid participating inputs still fail closed as in 440.
- The sleep coverage view reports measured HR completeness and gaps; an older asynchronous refresh
  cannot replace a newer request. Coverage is not a probability of accuracy.
- The optional comparison view shows HRV, resting HR, recovery and sleep-stage total differences,
  the number of paired observations, and signed bias (Safw minus WHOOP). Existing off-by-default
  receiver/consent behavior is unchanged. No external health data was retrieved for this change.
- Glucose history code, screens and tests have been removed. There is no diabetes risk model,
  glucose inference, or new glucose permission request. Existing upstream Health integration remains.
- Build number is 441. App identity remains `app.m1.mynoop.noop`, widget identity remains
  `app.m1.mynoop.noop.widgets`, and the database and App Group identities are unchanged.

## Verification boundary

Regression fixtures cover delayed/partially overlapping sleep exclusions, current corrected sleep
bounds, source isolation, malformed intervals, usable and unusable recovery baselines, and agreement
between the recovery score, its driver rows and its diagnostic trace. These are synthetic software
tests, not measured physiological accuracy. The full public workflow additionally tests the upstream
packages and macOS app, builds the actual Release iOS IPA, and launches normal/large-text simulator
screens. Source `64b68aa96a43de5eda3b7997f61b5c3dd8867e5d` passed
[workflow 40677344405](https://github.com/M1-0/safw/actions/runs/40677344405), including the final
aggregate gate, on attempt two. The first simulator job timed out during diagnostic collection
after all 46 captures; its retry completed on unchanged source. The successful package/app jobs
and Release IPA remain from attempt one. [build-441.json](build-441.json) records the test counts,
job IDs, visual-review boundary and exact IPA hash. Subsequent evidence-only documentation edits
do not change the tested executable source.

This is the personal iOS overlay. Shared Swift recovery hardening is applied during its Apple build;
the separately released upstream Android application is not changed or claimed to be updated.
Bluetooth commands, protocol decoding, sleep-stage model weights and upstream database schemas are
unchanged. No synthetic fixture is represented as the owner's real strap data.

## What would establish real accuracy

WHOOP agreement is a useful compatibility comparison, not independent ground truth. A lower
difference from WHOOP cannot establish that Safw is more accurate than WHOOP. No such result has been
measured for this build, and no accuracy percentage or superiority claim is justified.

1. Freeze the algorithm/version and analysis rules before evaluating held-out nights. Keep tuning
   nights separate. Record all missing, excluded and ambiguous intervals, not only successful pairs.
2. For HR and RMSSD, use synchronized independent ECG-derived reference intervals. Compare identical
   time windows and units; account for invalid beats before computing HRV. Report paired count,
   availability, bias and absolute error, with uncertainty and agreement limits where appropriate.
3. For sleep stages, use independently scored polysomnography in aligned epochs, including awake
   time and wake after sleep onset. Report a stage confusion matrix and per-stage metrics as well as
   total-duration error. Nightly WHOOP API stage totals cannot establish epoch-level staging accuracy.
4. Include changing inputs across nights and activity conditions. To claim superiority, compare Safw
   and WHOOP on the same independent reference observations with a prespecified endpoint and paired
   uncertainty analysis. A recovery composite has no single universal laboratory percentage; assess
   a predefined real-world outcome separately rather than treating the WHOOP score as truth.

Primary-methodology sources reviewed on 2026-10-28 (these studies do not validate Safw or WHOOP 5):

- AASM, *Consumer Sleep Technology: An American Academy of Sleep Medicine Position Statement*
  (2018), https://pmc.ncbi.nlm.nih.gov/articles/PMC5940440/
- Bellenger et al., *Wrist-Based Photoplethysmography Assessment of Heart Rate and Heart Rate
  Variability: Validation of WHOOP* (2021), https://pmc.ncbi.nlm.nih.gov/articles/PMC8160717/
- Miller et al., *A Validation of Six Wearable Devices for Estimating Sleep, Heart Rate and Heart
  Rate Variability in Healthy Adults* (2022), https://pmc.ncbi.nlm.nih.gov/articles/PMC9412437/

No physical strap session, ECG, polysomnography, real WHOOP OAuth connection or installed-device
update was available in this run. Those limitations remain after a successful software build.
