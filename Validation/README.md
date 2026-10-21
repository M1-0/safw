# Automatic personal comparison

This is an opt-in feature for the personal iPhone fork, not an upstream NOOP feature.
It collects a comparison without daily screenshots, transcription or switching between apps.
It **does not implement a new recovery or sleep algorithm**, automatically train a model, or prove
clinical accuracy. Installation alone is insufficient: the receiver, TLS and WHOOP OAuth app must
be configured once. Build 439 passed Apple CI and simulator launches and produced a real unsigned
IPA. The connection has not been tested with a real WHOOP account or physical strap.

## Data flow

1. The owner runs this single-user receiver on a computer they control behind HTTPS.
2. The phone stores that receiver's origin and random owner pairing token in its own Keychain.
   The user explicitly enables comparison and signs in to WHOOP in the system browser.
3. OAuth code exchange and refresh happen **only on the receiver**. The WHOOP client secret and
   upstream access/refresh tokens never enter the IPA, UserDefaults, reports or repository.
4. After a data refresh, foreground entry, or an iOS-granted background wake, the phone sends up
   to 90 days of computed per-sleep totals, local recovery/HRV/RHR, capture time, hashed device id,
   source/quality flags and a capture-settings fingerprint. It does not send names, email,
   location, raw PPG or raw R-R. Nothing is exported until configured and enabled.
5. The receiver pulls the official v2 recovery/sleep collections at most once every six hours,
   following pagination and rotating refresh tokens. It only does this in response to an
   authenticated comparison upload (or an explicit owner `sync` command), not a hidden scheduler.
   Disabling the phone switch stops further automatic uploads and thus further automatic pulls.
6. The report groups different devices and capture settings separately and returns numeric
   differences to the phone. The assistant has **no automatic access** to the receiver or phone.
   A later review needs a report shared by the owner or a separately configured authenticated
   connection. This service does not send data to ChatGPT or any developer.

## What is compared

- Candidate rows are read directly from the active physical strap's `-noop` computed namespace,
  not `Repository.days`, which deliberately favors imported WHOOP values on the dashboard.
- A recovery comparison requires a locally measured current input provider, HRV, and one unambiguous
  main block of at least three hours that day. Legacy/unknown input provenance is excluded.
- This source check does **not** establish complete independence of the existing algorithm's
  historical baselines: older manually imported physiology may have contributed to them. The report
  explicitly states `baseline_independence_verified: false`. It must not be used as proof of a
  fully independent post-subscription replacement. A raw-only baseline study remains separate work.
- Nights are matched by actual UTC interval overlap (intersection over union >= 0.5). Naps,
  ambiguous matches, duplicate use of a reference night, sparse/unknown motion, manually edited
  sleep bounds and reference no-data intervals cannot silently inflate the headline metric.
- Stage comparisons are **nightly minute totals**, never epoch-level classification accuracy.
  The official API supplies totals and does not expose the full hypnogram.
- Metrics include pair count, mean absolute difference and signed bias. Null/missing values never
  become zero. Unmatched, ambiguous and quality-excluded counts remain visible.
- The primary `groups` report freezes the first upload received between one and 24 hours after
  sleep ends, before fetching that upload's reference. Both receiver time and capture time are
  checked. The 24-hour deadline is an operational collection rule, not an accuracy threshold.
  Later recalculations cannot replace that snapshot, including when it had missing values or poor
  quality. Older/backdated uploads and legacy records remain outside the primary evaluation.
- All revisions remain available in `retrospective_groups` for debugging, using the latest seen
  revision; the phone's headline reads only the frozen primary report. A settings digest describes
  capture-time preferences, not proof of historical computation settings. This is not a blinded
  study: the owner can see WHOOP and baseline independence still needs separate verification.

## One-time owner setup

Python 3.12+ with `pip install -r Validation/requirements.txt` is sufficient for the receiver.
The current dependency is pinned to the version used by local verification. Install only in a
virtual environment. The server binds **127.0.0.1 only**; an existing, owner-controlled TLS reverse
proxy is required for iPhone access. Configure proxy access logs to omit query strings and
Authorization headers: the OAuth callback query temporarily contains an authorization code.
Do not expose wsgiref directly on a public interface and do not run simultaneous receiver instances.

Create a WHOOP developer app and register the exact HTTPS callback:

`https://<owner-origin>/oauth/callback`

Request only `read:recovery`, `read:sleep`, and `offline`. Keep the client secret server-side.
Store these variables in an untracked, owner-readable environment file (mode 0600):

```text
WHOOP_CLIENT_ID=<developer-app-client-id>
WHOOP_CLIENT_SECRET=<developer-app-client-secret>
SAFW_PUBLIC_URL=https://<owner-origin>
SAFW_OWNER_TOKEN=<random-owner-token-of-at-least-32-characters>
SAFW_DATA_KEY=<Fernet-key>
SAFW_DATABASE=/absolute/private/path/validation.sqlite
```

Generate the owner token with `secrets.token_urlsafe(32)` and the encryption key with
`cryptography.fernet.Fernet.generate_key()` in the owner's protected environment. Do not paste
them into chat, command-line arguments, source files or screenshots. Preserve the encryption key
outside SQLite: losing it makes saved records unreadable. SQLite payloads and OAuth tokens are
Fernet encrypted; the database is mode 0600. Avoid public backups.

Start `python3 Validation/service.py serve`. The `GET /health` endpoint reveals no account data.
Configure the origin and pairing token once in Safw's **Automatic comparison** page, enable it,
then tap **Connect WHOOP account**. The browser returns through `safw-validation://complete`;
the redirect carries no access or refresh token. If the phone remains open, a repository refresh
or **Sync comparison now** uploads the first batch. A background wake is requested no earlier
than six hours later; iOS may defer or skip it. Opening Safw provides the catch-up path.

The owner can fetch `GET /v1/report` with the pairing token, or use authenticated `DELETE /v1/data`
to erase receiver records and tokens. The latter does not revoke the WHOOP-side grant; revoke it
in the WHOOP account's integrations as well when permanently disconnecting. Turning the phone
switch off preserves previously stored records. No paid host, billing setting or cloud account
is created by this implementation. A computer/reverse proxy still needs to be available for sync.

## Verification and remaining gates

Run `python3 -m unittest discover -s Tests -p 'test_validation.py'` from the personal overlay.
Fixtures are synthetic. The tests cover OAuth state/expiry/replay, refresh rotation, paging,
reference publication, bounds/auth checks, encryption, revisions and comparison exclusions.
They do not make requests to a real WHOOP account or certify Apple API behavior.

Build 439 compiled both Apple targets and passed the configured tests in public CI; its iPhone 13
simulator run captured 44 screens, including comparison at normal and large text sizes. Before
claiming real device operation, exercise browser authorization and background expiration on the
physical iPhone 13 and verify the exact WHOOP redirect in the developer dashboard. The public
workflow runs Apple jobs only after public-repository checks. No private billing gate was retried.
This feature is intentionally iPhone-only; no upstream schema, Kotlin scorer, BLE command, shared
backup whitelist or standard NOOP computation changes.

Official integration references:
- https://developer.whoop.com/docs/developing/getting-started/
- https://developer.whoop.com/docs/developing/oauth/
- https://developer.whoop.com/api/
