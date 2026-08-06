# Finish-line runbook — everything outstanding, in order

Written 2026-08-05, when the backlog stood at **76 tracked tasks, 67 done, 9 open**. Every coding wave
(backend B1–B23, Android A1–A21, iOS I1–I20, web W1–W2) is merged and deployed. What remains is almost
entirely **portal and account work that only the account owner can do**.

This doc sequences that work. It does not replace the detailed references — [`store-readiness.md`](store-readiness.md)
(per-store checklists), [`h6-apple-portal-runbook.md`](h6-apple-portal-runbook.md) (Apple, values pre-filled),
[`azure-setup.md`](azure-setup.md) (infra) — it *orders* them and says what each one unblocks.

**Legend:** 👤 = only you can do it · 🤖 = agent can do it · ⏳ = waiting on a third party.

## What the agent can and cannot verify — read this before following any step

Written after the agent instructed the user to do two H9 steps that were **already done**, because it
treated an un-flipped ledger row as evidence of work outstanding. A `human` row means *nobody recorded
finishing it*, which is not the same as *it isn't finished*.

| System | Agent access | So it can verify… |
|---|---|---|
| GitHub | `gh` authenticated | secrets (names), variables, branch protection, Dependabot alerts, CI runs |
| Azure | `az` authenticated as `eric.wauters@dynex.be` | resources, Function App config, CORS, storage |
| Live web | plain `curl` | `/privacy`, `/terms`, `/delete-account`, `assetlinks.json`, AASA |
| Local repo | full | code, specs, builds, tests, signing of built artifacts |
| **Firebase** | **none** — no `firebase` CLI, no `gcloud`, no credentials | **nothing.** Auth providers, SMS region policy, authorized domains, registered apps, App Check, budget — all invisible |
| **Play Console** | **none** | nothing |
| **App Store Connect** | API key exists (upload only) | uploads; not listing/label state |

**Rule for the agent:** before presenting a `human` row as a task, verify it if the table above says you can.
If you cannot, say *"I can't check this — confirm whether it's already done"* rather than issuing it as work.

**Simulator permission alerts are sticky.** An iOS permission dialog that survives an app uninstall is a **stale SpringBoard alert**, not a live request — SpringBoard owns it, uninstalling does not dismiss it, and it ignores injected taps. Cost an hour on 2026-08-05 debugging a disclosure-ordering bug that did not exist. Run `xcrun simctl erase <udid>` before drawing any conclusion about permission ordering.

**To close the Firebase blind spot** (optional, ~2 min): `npm i -g firebase-tools && firebase login`. After
that the agent can run `firebase projects:list` / `firebase apps:list --project findly-71f7b`. Note that even
then, SMS region policy and authorized domains sit in Identity Platform and are not exposed by that CLI —
those stay user-confirmed.

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

**Verified behaviourally 2026-08-05**: a real Belgian (+32) number signed in successfully on a real device — so Blaze is active, real SMS delivery works, and Firebase phone auth is correctly wired end to end. This is the first *behavioural* confirmation of A2; it had until then been user-reported only, since Firebase is invisible to the agent. Note what it does **not** prove: the number tested is inside the allow-list, so non-BE/NL numbers remain silent by design.

**Do not** open SMS to all regions here — that's H8, and it belongs after App Check is *enforced*.

---

## Track B — M1-Android (the biggest remaining win) 👤 + 🤖

This is the shortest path to Findly being on every family Android phone. No store review, no waiting period:
the `waldo1001` account is an **Organisation** account under **Dynex bv**, so the 12-tester/14-day
closed-test rule does not apply.

It also fixes a live production bug: `assetlinks.json` currently serves **`CHANGE-ME` placeholder
fingerprints**, so Android App Links do not verify and a shared `https://…/g#CODE` join link opens the
browser instead of the app.

### B0 👤 ⏳ **Play account verification — BLOCKER, start it first, it has lead time**

Hit 2026-08-05: Play Console refuses app creation with *"Complete account verifications to create new apps."*
Nothing in Track B past B4 can proceed until Google clears it.

**Play Console → Settings → Developer account → Account details**, and complete every item flagged there.
For an Organisation account (`waldo1001`, Dynex bv, account ID `6979198494407001879`) that typically means:
legal entity name and address, the **D-U-N-S number** (already exists per the 2026-07-25 finding — reusable,
no need to re-apply), a verified contact email and phone, and sometimes a document upload proving the
address.

**Status 2026-08-05 (checked):** documents uploaded, **identity verification in review** — Console reads *"Google is verifying your identity... This may take a few days"*. Note it is **sequential, not one gate**: phone-number verification is itself blocked until the documents are approved (*"To verify your phone numbers, complete other verification tasks"*), so the sequence is identity review (days) → phone verification (minutes) → app creation unblocks. The completion notice goes to the **account owner's email**, not the Console — an unwatched inbox turns Google's delay into ours.

**Lead time is days, not minutes** — Google reviews it. Start it before anything else in this track, then go
do Track C and TestFlight while it runs. This is now the **single largest fixed delay to M1-Android**, taking
over the role the 14-day closed-test rule would have played had the account not been exempt.

Steps B1–B4 (keystore, secrets, local signed AAB) are **already done as of 2026-08-05** — the AAB is built and
verified signed with `CN=Eric Wauters, O=Dynex`, upload-key SHA-256
`3B:5C:9A:72:D0:15:8B:C1:CF:CD:0C:6C:6F:49:13:6B:25:1A:B3:F0:2C:83:8E:71:A9:4A:E9:FB:32:14:C3:18`.
So the moment verification clears, B5 (upload) is immediate.

### B1 👤 Create the release keystore (local, never committed) ✅ done 2026-08-05

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

### B4-B6 ✅ done 2026-08-06

Play account verification cleared; app created (`com.findly.android`, listing **Findly - Friends
Locator**); AAB `6 (1.0.0)` uploaded to internal testing; **Play App Signing active**.

Fingerprints, all three now registered in **both** `assetlinks.json` (live, verified) and Firebase:

| Key | SHA-256 | Signs |
|---|---|---|
| Play app signing (Google's) | `28:DE:48:B0:…:32:54` | what users install from Play |
| Upload (ours) | `3B:5C:9A:72:…:C3:18` | local + the sideloaded GitHub-release APK |
| Debug | `28:0D:FB:AC:…:45:08` | development builds |

**This closed a production bug**: `assetlinks.json` had served `CHANGE-ME` placeholders since W1, so
Android never verified the App Link and every shared `https://…/g#CODE` join link opened Chrome
instead of Findly — specs/007's whole public-join flow had never worked on Android. Registering all
three (rather than only Google's) is deliberate: two family members are on the sideloaded APK this
week, and the upload key is what signed it.

Also worth keeping: Play's App signing page shows **both** the app signing and upload fingerprints,
and using the upload one where the app signing one belongs fails **silently** — debug works,
production doesn't, nothing errors. The upload fingerprint Play displayed matched the one extracted
from the local keystore, which is how it was caught.

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
3. ✅ **Already done** (verified 2026-08-05): `az functionapp cors show -n func-findly -g Findly` returns
   `allowedOrigins: ["https://kind-plant-0fb99b003.7.azurestaticapps.net"]` with `supportCredentials: false`
   — correct, since the deletion page authenticates with an `Authorization` bearer header rather than
   cookies. `/delete-account` also returns `200`. So this track is two Firebase-console items, not four.
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

> **Every console answer for both stores is written out, paste-ready, in
> [`store-submission-pack.md`](store-submission-pack.md)** — listing copy, Play data-safety table, the
> background-location declaration text and video script, Apple privacy nutrition labels, review notes.
> It also opens with the honest caveat: production listings buy **reach**, not iteration speed — the
> Play internal track and TestFlight already deliver a fix to a family phone in minutes, while every
> production update goes through review.

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

### E0 👤 **Delete the sideload release the moment Play goes live** (user directive, 2026-08-05)

While Play verification was in review, the Android family build shipped as a **public GitHub release** —
`android-v1.0.0-build6`, carrying a signed APK and the install guide as its notes
([`install-android.md`](install-android.md) is the same content, kept in-repo).

```bash
gh release delete android-v1.0.0-build6 --yes
```

**Why it must go, not just fade:** it is a public download on a public repo, so it stays installable by
anyone who ever had the link — indefinitely, and with no update path. Once Play is serving the app, that
release is a stale fork of it: signed with the **upload** key rather than Google's app-signing key, so it
can never be upgraded in place and will silently diverge from whatever the Store is shipping. Leaving it up
means some family member reinstalls the frozen build a year from now and quietly runs old code against the
live backend.

Do this **after** confirming Play install works for at least one family member, not before — it is the only
Android distribution channel until then. Tell testers to uninstall the sideloaded copy first; the signature
mismatch blocks an in-place upgrade either way.

### E2 — Play (H5 tail) 👤 → ⏳

1. **Background-location declaration** + a demo video of the in-app prominent disclosure that precedes the
   runtime permission prompt. The flow is now **implemented as well as specified** — wired into the
   request path on Android (`7283783`) and iOS (`ed8182c`) on 2026-08-05, so the video can finally be
   recorded of something that exists. Declaration text + shot list: `store-submission-pack.md` §2.3.
   Historically the slow part of review — budget time.
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
