# Store readiness — Google Play & Apple App Store

The convention use case (specs/007, 000 §D15/D16) requires strangers to *install* the app, which means real store distribution (000 §Architecture already commits to full publishing). This is the runnable checklist; the backlog rows are H5 (Play), H6 (App Store), H7 (legal & naming), plus coding tasks A7 (release signing) and W1/A6/I6 (join links).

## 0. Hard gates — nothing ships to a store before these

| Gate | Why | Tracked as |
|---|---|---|
| **Privacy policy + Terms** authored and hosted (`https://{JOIN_LINK_HOST}/privacy`, `/terms`) | Both stores require a privacy policy URL for location apps; GDPR requires it for EU users regardless | H7 (hosting needs H4/W1) |
| **Naming / trademark decision — DONE 2026-07-25** | "Where's Waldo/Wally" is the book franchise's mark (000 §O10). **Decided:** public name = **Findly**; bundle ids `com.findly.*`. Removes the franchise-branding risk for store listings + printed QR | H7 (legal half — privacy/ToS — still open) |
| **Privacy endpoints** (data export + account/family delete) | 000 §O7 says "before any public release" — and Google Play's account-deletion policy *requires* a deletion path for apps with sign-in. **Spec DONE 2026-07-25: [`specs/008`](../specs/008-privacy-endpoints.md)** (wire shapes 001 §13, storage 002 §4.2) | implementation: B17–B19 (backend), W2 (web `/delete-account` page), A8/I8 (clients), H9 (Firebase web app + CORS) |
| **App Check enforced** on both platforms | Precondition for open-mode SMS (006 §6.3); also the right posture before strangers hold the app | H8 (after H2) |
| **Release signing** (Android) | Play requires a signed release; the release SHA-256 also feeds Firebase/App Check (006 §6.5) and `assetlinks.json` (007 §3) | A7 (wiring) + H5 (keystore) |

## 1. Google Play (H5)

1. **Developer account — RESOLVED 2026-07-25:** `waldo1001`, **Organisation account** under **Dynex bv** (Account ID `6979198494407001879`). Organisation accounts are **exempt** from the personal-account rule (created on/after 2023-11-13 → closed test with ≥12 testers for 14 days before production access). **No 14-day clock applies**, and the D-U-N-S number Google required to verify the organisation already exists and is reusable. Publisher name on the listing will be **Dynex bv**, consistent with the operator named in the privacy policy and ToS (H7).
2. **Release keystore:** create locally (never committed — `docs/security-review-checklist.md`); enroll in **Play App Signing** (Google holds the app signing key; you keep the upload key). The **app signing key's SHA-256** (from the Play Console, not your upload key) is what goes into the Firebase Android app registration (006 §6.5) and `assetlinks.json` (007 §3).
3. **A7 first:** `signingConfig` wired from CI/env references, `android.yml`'s release-build TODO resolved — no secret material in the repo. Once a real keystore exists, set these 4 **GitHub Actions repo secrets** (repo Settings → Secrets and variables → Actions — never commit them anywhere):
   - `ANDROID_KEYSTORE_BASE64` — the keystore file, base64-encoded (e.g. `base64 -i release.jks | pbcopy` on macOS, `base64 -w0 release.jks` on Linux)
   - `ANDROID_KEYSTORE_PASSWORD` — the keystore's store password
   - `ANDROID_KEY_ALIAS` — the signing key's alias inside that keystore
   - `ANDROID_KEY_PASSWORD` — the signing key's own password

   Generate the keystore (before Play App Signing enrollment below) with `keytool -genkeypair -v -keystore release.jks -alias <alias> -keyalg RSA -keysize 2048 -validity 10000`; get its SHA-256 fingerprint for the app-signing handoff (006 §6.5 / 007 §3) with `keytool -list -v -keystore release.jks -alias <alias>`. Full Play Console / Play App Signing enrollment steps belong to H5 below, not this note.
4. **Background-location declaration:** the app uses `ACCESS_BACKGROUND_LOCATION` (000 core functionality). Play requires a declaration + review with an in-app **prominent disclosure** before the runtime permission prompt (003 §11 covers the onboarding flow) and typically a demo video of that flow. Family-locator is an accepted use case — but the review is real; budget time.
5. **Data safety form** (truthful, matching the specs): precise location — collected, shared *with other app users* (family/group members), encrypted in transit, **not sold**, **deletable** (in-app + web, specs/008); phone number — collected by Firebase Auth for authentication (not by the backend, 006 §2). **Account deletion URL: `https://{JOIN_LINK_HOST}/delete-account`** (live once W2 + H9 land — a submission prerequisite).
6. **Content rating questionnaire**, target-API-level compliance (current Play policy floor), listing assets (icon, screenshots, feature graphic), support email.
7. **Store-review sign-in:** provide a Firebase **test phone number + fixed OTP** (006 §6.4) via the Play Console's app-access notes at submission time — the pair lives only in the two consoles, never in the repo.

## 2. Apple App Store (H6 — **enrollment COMPLETE**, Team ID `92A2K3Q7NH`)

> Corrected 2026-07-25: this section previously said "blocked on the Developer Program enrollment". That is stale — the Team ID is real and verified live in the served AASA (`92A2K3Q7NH.com.findly.ios`). Nothing Apple-side is enrollment-gated any more; the remaining items are portal work plus I9 (the `.xcodeproj` app target) before a build can be uploaded.

1. ~~Enrollment completes →~~ **Done** — Team ID recorded, AASA already complete and serving (007 §3); activate the **Associated Domains** entitlement (004 §3.5, prepared by I6).
2. Upload the **APNs auth key** to Firebase (the outstanding H2 §3.8 step — phone-auth app verification on device needs it).
3. **Apply for the Location Push Service Extension entitlement** immediately (000 §O1) — independent lead time, same account.
4. Create the App Store Connect app (bundle id per Firebase registration), wire **TestFlight** for the first real-device builds.
5. **Privacy nutrition labels** (match the data-safety answers: precise location, linked to identity, shared with other users; phone number for authentication), age rating, `NSLocationAlwaysAndWhenInUseUsageDescription` purpose strings that honestly describe family/group tracking (004 §7).
6. **Store-review sign-in:** same test-number approach via App Review notes.
7. The iOS `.xcodeproj` app target must exist first (specs/004 §1.1 — still a stub in `ios.yml`).

## 3. Shared

- Listing copy must not overpromise iOS background cadence (000 §O2 — intervals are targets, not guarantees).
- Printed convention materials (QR posters) come **after** H4 fixes `JOIN_LINK_HOST` and H7 fixes the name — the QR host is effectively permanent (007 §1).
- When a custom domain is added later (007 §6), old printed codes keep working; only new prints change.

## 4. Automated CI publishing (H10) — human prerequisites

H10 wired `android.yml` to publish to the Play **internal track** and `ios.yml` to upload to
**TestFlight** on every green push to `main`, gated on the secrets below being present (a green
build with no secrets is a silent no-op, not a failure — same pattern as A7's release signing).
**Deliberately internal-track / TestFlight only, forever** — promotion to a track real strangers
can reach (Play production/open/closed testing, or an App Store release) stays a manual console
action; nothing in either workflow can do it, on purpose (docs/security-review-checklist.md §2
least privilege).

### Google Play — one-time setup

1. **Create a Google Cloud service account** in the same GCP project backing the Play Console
   listing (Google Cloud Console → IAM & Admin → Service Accounts → Create). No IAM roles are
   needed on the GCP side — Play Console access is granted separately, in the next step.
2. **Invite it in Play Console → Users and permissions** (the Play Console account from
   §1 above, `waldo1001` / Dynex bv): Invite new user → the service account's email
   (`…@…iam.gserviceaccount.com`) → grant **only** *App access* for `com.findly.android` with
   permission **"Release to testing tracks"** (under Releases). **Do not grant "Release to
   production"** — that permission is what would let a compromised CI secret ship straight to
   real users; the whole point of gating CI to the internal track is that even a fully
   compromised `PLAY_SERVICE_ACCOUNT_JSON` still can't reach anyone outside the household without
   a human separately promoting the release in the Play Console.
3. **Download the JSON key** for that service account (Cloud Console → the service account →
   Keys → Add key → JSON).

   **Already done (2026-08-06):** the Google Play Android Developer API
   (`androidpublisher.googleapis.com`) is enabled on the `findly-71f7b` GCP project — every
   API-based publish 403s without it. If this project's GCP infra is ever rebuilt from scratch,
   re-enable it first: `gcloud services enable androidpublisher.googleapis.com --project=findly-71f7b`.
4. **GitHub secret:** repo Settings → Secrets and variables → Actions → New repository secret:
   - `PLAY_SERVICE_ACCOUNT_JSON` — the entire JSON key file's contents, pasted as-is (not
     base64-encoded — `serviceAccountJsonPlainText` in the publish action takes raw JSON).
5. **`MAPS_API_KEY`** (also gated the same way, and separately needed so CI-built artifacts stop
   shipping a blank map): the same Google Maps API key already used for local `assembleRelease`/
   `bundleRelease` (docs/azure-setup.md) — GitHub secret `MAPS_API_KEY`, plain key string.

### Apple TestFlight — one-time setup

The App Store Connect API key already used for manual laptop uploads
(`AuthKey_WV483G2U79.p8`, issuer `c21438a3-…`, §2 above) is reused for CI — no new Apple-side
key needs creating, just exporting the existing one into GitHub secrets:

1. `ASC_KEY_ID` — the 10-character Key ID (`WV483G2U79`).
2. `ASC_ISSUER_ID` — the issuer UUID (`c21438a3-…`, full value in App Store Connect → Users and
   Access → Integrations → App Store Connect API).
3. `ASC_API_KEY_P8` — the `.p8` file's contents, **base64-encoded** (same convention as A7's
   `ANDROID_KEYSTORE_BASE64`): `base64 -i AuthKey_WV483G2U79.p8 | pbcopy` on macOS, paste as the
   secret value. CI decodes it back to a file at the path `xcrun altool` expects
   (`~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8`) and shreds it after the upload
   step, win or lose.

### Verifying it worked

- **Android:** after a `main` push, check the `android-build` job log for "publish AAB to Play
  internal track", then Play Console → your app → Testing → Internal testing for the new build.
- **iOS:** check the `ios-build` job log for "release to TestFlight", then App Store Connect →
  TestFlight — a new build appears after 5–15 minutes of Apple-side processing (same delay as a
  manual upload).
- Both are gated on `github.ref == 'refs/heads/main'` — a PR build never attempts either, even
  with the secrets present, and a fork PR never has the secrets in the first place.

### Known limitation — workflow-file recreation resets `github.run_number`

Both workflows derive their published version/build number from `100 + github.run_number` —
that **workflow's own** run counter (see the "compute release version code"/"compute release
build number" steps in `android.yml`/`ios.yml`). GitHub resets `run_number` to 1 if a workflow
file is ever genuinely deleted and a new one registers in its place (editing the file, or its
git history, does not do this — only removal + re-registration does). If that ever happens, the
next CI-derived number restarts near 101, which is safe against every version published so far
but is not a guarantee for all time. **Before deliberately deleting/recreating either workflow
file:** bump that file's `+ 100` offset past whatever version/build number was most recently
published to that store, or the very next automated publish gets rejected for reusing (or going
backward past) an already-used number.
