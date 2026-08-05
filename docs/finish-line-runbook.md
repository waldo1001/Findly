# Finish-line runbook — everything outstanding, in order

Written 2026-08-05, when the backlog stood at **76 tracked tasks, 67 done, 9 open**. Every coding wave
(backend B1–B23, Android A1–A21, iOS I1–I20, web W1–W2) is merged and deployed. What remains is almost
entirely **portal and account work that only the account owner can do**.

This doc sequences that work. It does not replace the detailed references — [`store-readiness.md`](store-readiness.md)
(per-store checklists), [`h6-apple-portal-runbook.md`](h6-apple-portal-runbook.md) (Apple, values pre-filled),
[`azure-setup.md`](azure-setup.md) (infra) — it *orders* them and says what each one unblocks.

**Legend:** 👤 = only you can do it · 🤖 = agent can do it · ⏳ = waiting on a third party.

---

## Track A — quick wins (~15 min, do first)

Neither blocks anything else, and both close a real gap that exists *today*.

### A1 👤 Enable Dependabot alerts

Repo → **Settings → Code security and analysis** → enable **Dependabot alerts** (and optionally security updates).

**Why it matters now:** A18 shipped `dependabot.yml` plus a dependency-graph submission workflow, and both
reviewers verified via `gh api` that alerts are `disabled` repo-wide. GitHub therefore accepts the submitted
graph and **evaluates it against nothing** — no alert will ever fire for `play-services-*`, `androidx.*`,
Firebase or `maps-compose`, however many CVEs land. Until this toggle flips, A18's motivating problem
("no Android dependency has ever been checked against a vulnerability database") is still literally true.

**Verify:** `gh api repos/waldo1001/Findly/vulnerability-alerts` returns 204, not 404.

### A2 👤 Firebase tail on `findly-71f7b` (H2)

Firebase console → the `findly-71f7b` project:

1. **Blaze plan + budget alert €5.** Phone auth needs Blaze for real numbers.
2. **Authentication → Settings → SMS region policy →** allow **BE** and **NL** only (family mode, specs/006 §6.3).

**Why:** without this, sign-in with a *real* phone number fails. The test number
(`+32 470 00 00 01` / `123456`) works regardless, which is exactly why this gap can hide until a family
member tries to sign in.

**Do not** open SMS to all regions here — that's H8, and it belongs after App Check is *enforced*.

---

## Track B — M1-Android (the biggest remaining win) 👤 + 🤖

This is the shortest path to Findly being on every family Android phone. No store review, no waiting period:
the `waldo1001` account is an **Organisation** account under **Dynex bv**, so the 12-tester/14-day
closed-test rule does not apply.

It also fixes a live production bug: `assetlinks.json` currently serves **`CHANGE-ME` placeholder
fingerprints**, so Android App Links do not verify and a shared `https://…/g#CODE` join link opens the
browser instead of the app.

### B1 👤 Create the release keystore (local, never committed)

```bash
keytool -genkeypair -v -keystore release.jks -alias findly -keyalg RSA -keysize 2048 -validity 10000
```

Store `release.jks` and both passwords in your password manager. If this file is lost **before** Play App
Signing enrolment, you cannot ship an update to an already-published app — after enrolment Google holds the
app signing key and a lost upload key is recoverable.

### B2 👤 Set the four GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions**. Confirmed empty today (`gh secret list` returns nothing).

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i release.jks \| pbcopy` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `findly` (or your alias) |
| `ANDROID_KEY_PASSWORD` | key password |

A7 already wired `signingConfig` to read these, so nothing in the repo changes.

### B3 👤 Play Console — create the app and enrol in Play App Signing

Create the app (publisher **Dynex bv**), then build and upload the first release to the **internal testing**
track. Enrol in Play App Signing during the first upload.

### B4 👤 Copy the **app signing** SHA-256

Play Console → **Setup → App integrity → App signing**. Take the **app signing key** SHA-256, *not* your
upload key — this is the single most common mistake here, and it produces links and phone-auth that fail
silently in production while working in debug.

Also grab your debug fingerprint, so links and sign-in work in debug builds too:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

### B5 👤 Register both fingerprints in Firebase

Firebase console → Project settings → the `com.findly.android` app → **Add fingerprint**. Add the app-signing
SHA-256 **and** the debug SHA-256 (specs/006 §6.5).

### B6 🤖 Update `assetlinks.json` and redeploy

Hand the agent both SHA-256 fingerprints — they are **public** values, safe to paste in chat and to commit
(they already ship in every APK). The agent replaces the two `CHANGE-ME` placeholders in
`web/join/.well-known/assetlinks.json`, commits, and the W1 workflow redeploys.

**Verify:** `curl -s https://kind-plant-0fb99b003.7.azurestaticapps.net/.well-known/assetlinks.json`
shows real fingerprints, then tap a join link on a real Android phone — it must open Findly, not Chrome.

### B7 👤 Add the family as internal testers

Play Console → internal testing → testers. They install from the Play link.

**→ M1-Android reached.**

---

## Track C — H9, privacy-page infrastructure 👤 + 🤖

Blocks H8, and without it the `/delete-account` page cannot actually sign anyone in — which matters because
Play's data-safety form requires a working account-deletion URL.

1. 👤 Firebase console → register a **web app** in `findly-71f7b`.
2. 👤 **Authentication → Settings → Authorized domains** → add the SWA host
   (`kind-plant-0fb99b003.7.azurestaticapps.net`).
3. 🤖 CORS on `func-findly` for that origin, allowing `DELETE` + `Authorization` (agent can run the `az` CLI
   if you are logged in; otherwise Azure Portal → Function App → CORS).
4. 👤 Register the **web** App Check provider (reCAPTCHA). Must exist **before** H8 flips enforcement, or the
   deletion page's sign-in breaks the moment enforcement turns on.

---

## Track D — before the family uses it for real 👤

**Account reset (specs/006 §8) — one-time, and it must happen before real onboarding, not after.**

1. Delete every Firebase test user from `findly-71f7b`.
2. Wipe test data from `stfindly` (tables + blobs).
3. Then: parent creates the family, invites members by code, sets up geofences (Home, School…) and per-device
   intervals.

Easy to forget, and awkward to undo once real location history is interleaved with test rows.

---

## Track E — M2, public release

### E1 — Apple (H6 tail) 👤 → ⏳

Steps 1–7 of [`h6-apple-portal-runbook.md`](h6-apple-portal-runbook.md) are **done**: both App IDs, App Store
Connect record (Apple ID `6797994768`, listing name *Findly - Friends Locator*), APNs key `MS22L459T9`
uploaded, signing wired, builds uploading via `mobile/ios/scripts/release-testflight.sh`.

Remaining:

1. Register iOS **App Check** (App Attest) — also an H8 precondition.
2. **Privacy nutrition labels**, matching the Play data-safety answers exactly: precise location, linked to
   identity, shared with other app users; phone number for authentication.
3. Age rating; verify the `NSLocationAlwaysAndWhenInUseUsageDescription` purpose strings honestly describe
   family/group tracking.
4. **App Review notes:** the Firebase test number + fixed OTP. These live only in the two consoles — never in
   the repo.
5. Submit → ⏳ App Review → **M2-iOS**.

### E2 — Play (H5 tail) 👤 → ⏳

1. **Background-location declaration** + a demo video of the in-app prominent disclosure that precedes the
   runtime permission prompt (the 003 §11 / 009 §7 flow already matches policy). Historically the slow part
   of review — budget time.
2. **Data-safety form**, truthful and matching the specs: precise location collected, shared with other app
   users, encrypted in transit, not sold, deletable in-app and on the web; phone number collected by Firebase
   Auth for authentication, not by the backend. Account-deletion URL:
   `https://kind-plant-0fb99b003.7.azurestaticapps.net/delete-account` (needs Track C live).
3. Content rating questionnaire, target-API-level compliance, listing assets, support email.
4. App-access notes with the test number + OTP.
5. Submit → ⏳ review → promote to production → **M2-Android**.

---

## Track F — only when going beyond the family (H8) 👤

Requires H2 (A2 above), H6 (E1), **and** H9 (Track C) all done first.

1. App Check **enforced** on both platforms — and the web app must already carry its provider (Track C step 4).
2. SMS regions opened to all.
3. Budget alert raised to €25.
4. Incident runbook per specs/006 §7.

Not needed for family use: the BE/NL allowlist from A2 is sufficient.

---

## Agent-side, in parallel 🤖

Independent of everything above; none of it blocks you.

- **I18** — a SwiftUI rendering harness. Worth doing rather than declining: I16 (`@StateObject` ownership,
  broke every screen) and I20 (a sheet inheriting the back action) were both caught by *review*, not by tests,
  and 606 passing tests could not have caught either. They are the same class of defect and it has now
  recurred once.
- **I19** — verify the I20 navigation fixes on a real screen. Blocked on one command that needs your password:
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Then check: back chevron on every pushed
  screen and not on Home/SignIn; **no** chevron on the geofence editor sheet; cold start with a live session
  lands on Home with no SMS prompt. Also decide swipe-back.
- **I20-followup** — decide whether session restore should sit behind a biometric lock. Since I20, device
  access alone reaches the family's live locations; the SMS prompt was previously an accidental second gate.
- **Design pass** — [`design-prompt.md`](design-prompt.md) is authored but nothing tracks *applying* a
  generated design to the token layer. This is the "polishing" work, and it currently exists in no backlog row.

---

## Ordering summary

```
A1 A2            quick wins, ~15 min, no dependencies
   └── B1…B7     M1-Android  ← biggest win; also fixes live broken App Links
   └── C         H9 → unblocks H8, makes /delete-account work
        └── D    account reset, then real family onboarding
             └── E1/E2  store submissions → M2
                  └── F  H8, only if opening past the family
```
