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
4. **Background-location declaration:** the app uses `ACCESS_BACKGROUND_LOCATION` (000 core functionality). Play requires a declaration + review with an in-app **prominent disclosure** before the runtime permission prompt (003 §11 covers the onboarding flow) and typically a demo video of that flow. Family-locator is an accepted use case — but the review is real; budget time. **Persistent notification (amended 2026-09-06, 009 §1.3/§3.2, 000 §D19):** at the four "Live" sync intervals — **5, 10, 15 and 30 minutes**, not only 5/10 as originally scoped — the app keeps a low-power foreground presence service running with the always-visible "Findly is sharing your location" notification (Play's own requirement for background location, §3.2); the demo video and declaration text should show the persistent notification appearing at all four of those intervals, not just the fastest two. The three "Battery saver" intervals (1 hour–1 day) have no presence and no persistent notification — reporting is opportunistic there.
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
   production"** *(superseded 2026-10-05 by the user's decision; see §5)* — that permission is what would let a compromised CI secret ship straight to
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

## 5. Releasing to production — the "Release to stores" workflow (A57 / I60, normative)

**Why this exists.** On 2026-10-05 publishing two builds that CI had already built took roughly 25 console screens across Play Console and App Store Connect. Every recurring step has an official API, and CI already holds a credential for each store. This section is the contract the automation implements.

**Trigger.** `.github/workflows/release-stores.yml`, `workflow_dispatch` only — **never** on push. Inputs: `platforms` (`both` | `android` | `ios`, default `both`), `release_notes` (required, plain text, ≤ 500 characters, used for every locale), `dry_run` (boolean, default `false`). Every job that can change a store runs in the GitHub environment **`production`**: required reviewer `waldo1001`, deployable from `main` only. One click to run, one click to approve.

**Dry run.** With `dry_run: true` each platform performs every read and validation it would perform for real and prints the exact plan (what it would set, on which version or build), then changes nothing: Play opens an edit, validates it and deletes it without committing; App Store Connect makes GET requests only. The first run of each platform after any change to these scripts MUST be a dry run. For an iOS version that does not exist yet, the dry run still checks every blocker (other versions, open submissions) and reads the **previous live version's** App Review details as a proxy; the check after creation stays authoritative. Release notes are limited to **500 characters on both platforms** (Play's limit), so a `both` run can never split.

**Android (A57).** Authenticates with the existing service-account key. **Decided by the user 2026-10-05:** that service account is granted **"Release to production"** for `com.findly.android`, superseding §4's testing-tracks-only rule; the accepted trade-off is that the key itself can now publish to production. **Credential placement (normative — A57 reviews, HIGH):** the key MUST NOT be a repository secret, because repository secrets reach every same-repo pull-request build. It lives only as an **environment secret** `PLAY_SERVICE_ACCOUNT_JSON` in **`production`** (required reviewer, main only — read by the release job) and in **`play-internal`** (no reviewer, main only — read only by `android.yml`'s internal-track publish job, which never runs on `pull_request`). The build job holds no Play credential. Play still reviews every production release. Steps, in one Play edit:
1. Read the **Internal testing** track and take the version code(s) of its current `completed` release — the one with the **highest** version code, whatever order Play lists releases in. If none exist, fail.
   **Production safety (A57 review):** consider every non-draft production release. If one is **`halted`**, fail closed (a halted build was stopped deliberately; never resume or replace it automatically). If an **`inProgress`** release carries a version code ≥ Internal's, fail closed (it would be a downgrade of a live rollout).
2. Set that release on **Production** (`status: completed`, full rollout) **and on Closed testing – Alpha**, with the release notes in `en-GB` (plus any other language the store listing has).
3. Validate, then commit with **`changesInReviewBehavior=ERROR_IF_IN_REVIEW`**. Play's default (`CANCEL_IN_REVIEW_AND_SUBMIT`) would silently cancel every change already in review and resubmit; the explicit value makes Play refuse instead. A refusal with `CHANGES_ALREADY_IN_REVIEW` is reported as **"production has changes in review — stopped"** (a successful run that changed nothing), matching iOS's in-flight stop. Any other commit refusal (e.g. "cannot be sent for review automatically") **fails**, deletes the edit, and tells the operator the next step: Play Console → Publishing overview → Send changes for review. The tool never sets `changesNotSentForReview`.
4. If Play reports that production already carries that version code, report "nothing to release" and succeed without committing.

**Android internal-track upload (A59, normative).** `android.yml`'s `publish-internal` job uploads every main build to the Internal testing track with the same tool (`tools/play-release`, an `upload-internal` mode), **not** `r0adkll/upload-google-play`: that action cannot pass `changesInReviewBehavior`, so Play applies its default `CANCEL_IN_REVIEW_AND_SUBMIT` and an ordinary push would **cancel a production review in progress**. Observed 2026-10-05: with production 234 in review, Play refused the old `changesNotSentForReview: true` ("Changes are sent for review automatically. The query parameter changesNotSentForReview must not be set") — dropping the flag would have committed with the cancelling default. Steps, in one edit: upload the AAB (`edits.bundles.upload`) → set the Internal track to `{versionCodes: [uploaded], status: completed}` → commit with **`changesInReviewBehavior=ERROR_IF_IN_REVIEW`**. Outcomes: committed → done. Refused with `CHANGES_ALREADY_IN_REVIEW` → **deferred**: delete the edit, emit a `::notice::` ("production review in progress — internal upload deferred; the next main build after the review uploads"), exit 0. Refused because Play requires `changesNotSentForReview` (the post-rejection state, e.g. "Changes cannot be sent for review automatically") → **retry the commit once** with `changesNotSentForReview=true` **and** `ERROR_IF_IN_REVIEW`. Anything else → fail, edit deleted. Credential and masking rules as for the release job; the job keeps `environment: play-internal`. **Posture change, accepted (A59 security review):** the old action always committed with `changesNotSentForReview: true`, so it could never send anything for review; the first commit now omits that flag, which in Play's terms sends the edit's changes for review. The edit holds only an Internal-track release (no review needed), `ERROR_IF_IN_REVIEW` is always set, and Play refuses auto-sending exactly when unsent changes are pending — in which case the retry sets the flag. **Unlike the release job, nothing approves this job:** it runs on every push to `main` with a production-capable key, so protection of `main` is the control (see A58).

**iOS (I60).** Authenticates with the existing App Store Connect API key (`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_KEY_P8`, role **App Manager**) via an ES256 JWT. App `com.findly.ios` (Apple ID `6797994768`). **Credential placement (normative — I60 security review, same class as Android's):** the three `ASC_*` values MUST NOT be repository secrets. They live only as **environment secrets** in **`production`** (read by the release job) and in **`testflight`** (no reviewer, main only — read only by `ios.yml`'s TestFlight release job, which never runs on `pull_request`; the PR build job holds no App Store credential). Same key in both, by the user's 2026-10-05 reuse decision.
1. Pick the newest build whose processing state is `VALID`; its marketing version is the version to release.
2. Find that `appStoreVersion`, or create it if absent. If it is already **in flight** (waiting for review, in review, accepted, pending release, processing), report the state and stop without changing anything, as a successful run. If it is already **live** (released or replaced), **fail** without changing anything, with the hint "bump MARKETING_VERSION in mobile/ios/project.yml": a green run that shipped nothing would hide the I56 mistake. *(Clarified 2026-10-05, I60.)* **Other versions (I60 code review):** Apple allows one non-live version at a time, so the tool MUST list **all** iOS versions, not only the matching one. If **another** version is in flight, stop and name it. If another version is an editable draft or rejected, fail and name it. In both cases, do so before any change.
3. Set `whatsNew` on every localization to the release notes.
4. Attach the build; set release type **automatic after approval**, no phased release.
5. Verify the App Review details (sign-in required plus demo account) exist; the app carries them forward from the previous version. If they are missing, fail with a clear message rather than guess.
6. Create a review submission containing the version (or reuse an open draft in `READY_FOR_REVIEW` that holds nothing else), and submit it. **Before any change** (dry run too), check every review submission for the app: one in `UNRESOLVED_ISSUES`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `CANCELING` or `COMPLETING` → fail, naming the state, with the hint *resolve or resubmit it in App Store Connect* (appeals and rejection responses stay manual).

**Out of scope, stays manual (Claude in Chrome may read and stage, the user presses submit):** legal agreements, first-time and changed policy declarations (content rating, data safety, age-rating questionnaires, App access), appeals, store listing text and screenshots.

**Output.** Each job writes a GitHub step summary: platform, version or build (Android: release name *and* version codes), what changed, the store state afterwards (Android: the production release's `releaseLifecycleState` from the read-only `applications.tracks.releases.list`, e.g. IN_REVIEW), and a console link.

**Tool CI and the privileged job.** The tools' tests run on every pull request and push in a workflow **with no secrets** (`tools.yml`). Both credentialed jobs — the release job and `android.yml`'s `publish-internal` — run only `npm ci --ignore-scripts` and the TypeScript build before the step that holds the credential, never the test runner. Any change to a `tools/*/package-lock.json` is therefore security-relevant (Dependabot does not watch these lockfiles). Node 24, matching `backend.yml`. Derived credentials (the signed assertion, access tokens) are registered with `::add-mask::` before use, and Google's token endpoint is pinned to `https://oauth2.googleapis.com/token`.

