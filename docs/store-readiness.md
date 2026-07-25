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
