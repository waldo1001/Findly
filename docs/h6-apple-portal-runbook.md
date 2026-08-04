# H6 — Apple portal runbook

**Do these in order. Each step is one action. Nothing here depends on anything below it.**

Companion to [`docs/store-readiness.md`](store-readiness.md) §2 (that's the checklist; this is the procedure).

Team ID **`92A2K3Q7NH`** · enrollment COMPLETE · I9 and I15 merged, so a build can be produced and uploaded.

---

## Step 1 — Register the app's App ID

<https://developer.apple.com/account> → Certificates, Identifiers & Profiles → **Identifiers** → **+** → App IDs → App

- **Description:** `Findly`
- **Bundle ID:** select **Explicit**, enter `com.findly.ios`
- Tick these three capabilities:
  - **Push Notifications** — all FCM-routed push (001 §8)
  - **Associated Domains** — public join links (007 §3)
  - **App Attest** — App Check on iOS, blocks H8 (006 §6.3)
- Continue → Register

✅ **Done when:** `com.findly.ios` is listed under Identifiers with those three capabilities.

---

## Step 2 — Register the extension's App ID

<https://developer.apple.com/account> → Certificates, Identifiers & Profiles → **Identifiers** → **+** → App IDs → App

(Registering in step 1 returns you to the Identifiers list — click the **+** next to the "Identifiers" heading again.)

- **Description:** `Findly Notification Service`
- **Bundle ID:** Explicit, `com.findly.ios.NotificationService`
- **No capabilities** — the extension declares no entitlements, no App Group, no Keychain, no network.

This is new from I15. A signed build fails without it.

✅ **Done when:** both identifiers appear under Identifiers.

---

## Step 3 — Create the App Store Connect record

<https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**

- **Platforms:** iOS
- **Name:** `Findly - Friends Locator` — **registered 2026-08-04** (plain hyphen, not an em dash — this is the exact string in App Store Connect)
  - The bare name `Findly` is **already taken** on the App Store (tried 2026-08-04: *"The app name you entered is already being used"*) — there are at least four Findly apps, including a Bluetooth device-finder. The descriptor form was checked and no app holds this string.
  - **This is the store listing name only.** The home-screen name stays `Findly` (`CFBundleDisplayName` in `Findly/Info.plist`), and every internal identifier is unchanged: `com.findly.ios`, `com.findly.ios.NotificationService`, Firebase `findly-71f7b`, the join-link host. Nothing in the repo changes because of this.
  - If Apple still rejects it, vary the descriptor (`Findly: Shared Location`, `Findly — Whereabouts`) — do **not** touch bundle ids, which would mean redoing steps 1–2 and recreating the Firebase project.
  - Use this exact string anywhere the store listing name is needed (App Review notes, marketing, the Play listing if you want them consistent).
- **Primary Language:** English
- **Bundle ID:** `com.findly.ios` from the dropdown (absent = step 1 didn't take)
- **SKU:** your own internal string, never public — `findly-ios-001`
- **User Access:** Full Access

→ **Create**

Then read the **Apple ID** off it: Apps → Findly → **App Information** → General Information → **Apple ID** (~10 digits). It's also in the URL: `appstoreconnect.apple.com/apps/`**`1234567890`**`/…`

✅ **Done 2026-08-04.** App Store Connect record created:

| | |
|---|---|
| **App Apple ID** | `6797994768` |
| **SKU** | `findly-ios-001` |
| **Store listing name** | `Findly - Friends Locator` |
| **Bundle ID** | `com.findly.ios` |

(The Apple ID is public information — it's the `id…` in every App Store URL — so it's fine to record here. The eventual public URL will be `https://apps.apple.com/app/id6797994768`, which 404s until the app is actually released.)

---

## Step 4 — Submit the Location Push entitlement request

<https://developer.apple.com/contact/request/location-push-service-extension/>

Must be submitted by the **Account Holder** role. Approval is account-level: once granted, `com.apple.developer.location.push` becomes available as a capability on your App IDs.

**Form answers:**

| Field | Answer |
|---|---|
| App name | `Findly` |
| Bundle ID | `com.findly.ios` |
| App Apple ID | `6797994768` |
| App Store URL | *"Not yet released; app record created in App Store Connect, first build going to TestFlight."* |

**Describe your app:**

> Findly is a private family location-sharing app. Members of a family (or a temporary, time-limited group) can see each other's locations on a shared map. Every device opts in explicitly, sharing intervals are chosen per device by the person who owns it, and any member can pause sharing from their own device at any time. Location data is only ever visible to members of the same family or group — it is never sold, shared with third parties, or used for advertising. The app provides full in-app export and deletion of stored location history.

**Describe how your app will make use of the Location Push Service Extension:**

> Only for the app's on-demand "locate" feature. When one family member requests a current location for another member's device, the app needs a single, high-accuracy fix from that device at that moment. Today this is implemented with a silent background push (`content-available: 1`), which iOS budgets and coalesces — the requested update often does not arrive until the device wakes for an unrelated reason, so the requester is left looking at a stale last-known position. The Location Push Service Extension is the mechanism designed for this: a power-efficient, on-demand location query when the app is not running. It returns one fix per request and is not used for continuous or background tracking — periodic location sharing uses ordinary background scheduling and significant-location-change monitoring, entirely separately from this extension.

**What will trigger a location push:**

> An explicit, user-initiated request. A family member taps "locate" on another member's device in the app; the backend sends exactly one location push to that specific target device. Nothing automated, scheduled, or geofence-driven ever triggers one. Requests expire after 60 seconds, and a concurrent request for a device that already has one pending is coalesced into the existing request rather than sending a second push.

**On average, how many location pushes will your app send a user per day:**

> Typically fewer than 5 per device per day, since each one requires a person to deliberately tap "locate". The backend enforces a hard ceiling of 100 locate requests per family per UTC day, shared across all members, and coalesces concurrent requests for the same device so repeat taps do not multiply pushes.

The numbers are enforced in code — `locateRequestsPerDay: 100` in `backend/src/domain/plan.ts`, the 60s expiry and coalescing in specs/001 §6.1. Adapt the prose, keep the numbers.

⚠️ **Do NOT add `com.apple.developer.location.push` to `Findly.entitlements` until Apple grants it** — an ungranted entitlement breaks code signing. The file already carries a commented-out block saying so.

**Expect:** days to weeks, sometimes no reply, approval not guaranteed. Nothing else in H6 or in shipping depends on it — the app ships a working best-effort fallback (001 §8 payloads are designed for both paths).

✅ **Submitted 2026-08-04.** Awaiting Apple. Nothing downstream waits on the outcome — if it's granted, it becomes its own spec'd task (see "After H6").

---

## Step 5 — Create the APNs key and upload it to Firebase

**The highest-value step.** It unblocks iOS on-device phone sign-in *and* App Check, and App Check blocks H8.

1. <https://developer.apple.com/account> → **Keys** → **+** → tick **Apple Push Notifications service (APNs)** → Continue → Register
2. **Download the `.p8`. Apple allows this exactly once.** Put it in your password manager.
3. Note the **Key ID** (shown on the key page) and Team ID `92A2K3Q7NH`.
4. <https://console.firebase.google.com> → project **`findly-71f7b`** → ⚙️ Project settings → **Cloud Messaging** → iOS app configuration → **APNs Authentication Key** → Upload → the `.p8` + Key ID + Team ID.

**Part A done 2026-08-04:**

| | |
|---|---|
| Key name | `Findly APNs` |
| **Key ID** | `MS22L459T9` |
| Service | Apple Push Notifications service (APNs) |
| Team ID | `92A2K3Q7NH` |

⚠️ **The `.p8` file is the secret — never commit it** (`.gitignore` covers `*.p8`). The Key ID and Team ID above are *not* secrets: they're non-sensitive identifiers that pair with the key, they appear in Firebase config and in backend app settings, and they are useless without the private key itself. Recording them here is deliberate so a future session doesn't have to go hunting in the Apple portal.

APNs auth keys are **team-wide** — this one key serves `com.findly.ios` and the notification extension. Do not create a second.

✅ **Done when:** Firebase's Cloud Messaging tab shows the APNs key against the iOS app.

---

## Step 6 — Turn on real signing in the project

1. Edit `mobile/ios/project.yml` — uncomment `DEVELOPMENT_TEAM: 92A2K3Q7NH` in **both** targets (`Findly` and `FindlyNotificationService`; each has a `TODO(H6)` marker).
2. `cd mobile/ios && xcodegen generate` — **never hand-edit `project.pbxproj`**.
3. Leave `aps-environment` as `development`; Xcode switches it for distribution builds.

✅ **Done 2026-08-04** (commit `6cea39a`). `DEVELOPMENT_TEAM: 92A2K3Q7NH` is set on both targets, project regenerated via `xcodegen`.

**One thing this step needed that the original plan missed:** with a real team set, automatic signing tries to resolve a provisioning profile — and the `ios-build` CI job runs on a GitHub runner with no Apple credentials, so it would have gone red on `main`. `.github/workflows/ios.yml`'s simulator build therefore now passes `CODE_SIGNING_ALLOWED=NO`. Simulator builds never need signing, so the job still checks exactly what it should (the code compiles, the extension embeds) without depending on secrets CI deliberately lacks. Verified for real: the exact CI command locally, then `ios` green on the runner (run `30944953241`).

---

## Step 7 — Upload a build to TestFlight

### 7a. Machine prerequisites (done 2026-08-04 — read this if signing ever breaks)

Archive fails without a working signing identity, and this machine had none. What was needed:

1. **Xcode → Settings → Apple Accounts → +** — sign in with the Apple ID on the enrolled team (`apple@waldo.be`, team **Dynex**, role Admin).
2. Select the team → **Manage Certificates… → +** → create **Apple Development** *and* **Apple Distribution**.
3. **The trap:** certificates existed and Xcode showed them, but `security find-identity -v -p codesigning` reported **0 valid identities** and `codesign` failed with:
   ```
   unable to build chain to self-signed root for signer "Apple Distribution: Dynex (92A2K3Q7NH)"
   errSecInternalComponent
   ```
   Cause: the certificate is issued by **WWDR G3** (`OU=G3`), but the only WWDR intermediate in the keychain was the original **G1, expired 2023-02-07**. Apple Root CA was fine (present in system roots). The chain simply couldn't reach it. Fix:
   ```bash
   curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o /tmp/AppleWWDRCAG3.cer && security import /tmp/AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db
   ```
   Verified after: 2 valid identities, and `codesign -dvv` shows the full chain `Apple Distribution → WWDR → Apple Root CA`, `TeamIdentifier=92A2K3Q7NH`.

**Diagnostic worth reusing:** `security find-identity -v -p codesigning` lists only *valid* identities, so an incomplete chain shows as zero and looks identical to "no certificates at all". `security find-certificate -a` proves whether the certs exist; a real `codesign` attempt reveals *why* they're unusable. Also note `security find-certificate` does not search `/System/Library/Keychains/SystemRootCertificates.keychain` unless you name it — an apparently-missing Apple Root CA is usually a search-path artifact, not a real absence.

Also confirmed here: the **Dynex** team really is `92A2K3Q7NH` (the distribution certificate's own subject says so), matching what `project.yml` hardcodes.

### 7b. Archive and upload

1. Xcode → Product → **Archive**
2. Distribute App → **App Store Connect** → Upload
3. App Store Connect → your app → **TestFlight** → enable internal testing → install on your iPhone

Fill in while you're there:

- **Privacy nutrition labels** (must match the Play data-safety answers): precise **location**, linked to identity, **shared with other users**; **phone number** for authentication.
- **Age rating**.
- **App Review notes**: the test-phone-number sign-in approach — reviewers cannot receive a real SMS.

✅ **Done when:** the build installs on a real device from TestFlight.

---

## Step 8 — Test on the device

This is the point of all of it. A lot of iOS work is written, unit-tested, and has never run on real hardware.

1. **Phone sign-in** — needs step 5. Fails without it.
2. **Push arrival** — `LOCATE_REQUEST`, `SETTINGS_CHANGED`, `GEOFENCE_CONFIG_CHANGED` (001 §8).
3. **`GEOFENCE_EVENT` re-rendering via the I15 extension** — trigger a real geofence transition, confirm the notification shows the client-rendered title. **This is the only way to verify it**: `simctl push` provably never invokes a Notification Service Extension on Simulator, and app-extension targets can't be unit-tested directly.
4. **Universal Links** — tap `https://kind-plant-0fb99b003.7.azurestaticapps.net/g#CODE`, confirm it opens the app not Safari.
5. **Background location** — the "Always" permission dance; fixes keep flowing with the app closed.

---

## After H6

- **H8** (go-open switch) needs App Check *enforced* on both platforms — step 1's App Attest + step 5's key — and also waits on **H9**. Enforce before opening SMS regions, never the reverse.
- If Apple grants the Location Push entitlement, that's its own spec'd task: locate pushes move to direct APNs (`apns-push-type: location`, topic `<bundleId>.location-query`), adding an APNs credential to the backend and a `locationPushToken` to device registration (001 §4.1, §8.1). FCM cannot address location push tokens.

## Notes

- **Almost nothing here touches the repo.** The `.p8`, profiles and certificates are password-manager material. The only code change H6 produces is step 6's two-line uncomment plus the regenerated project file.
- The BGTask identifier `be.dynex.findly.refresh` keeps the pre-rename reverse-domain. It's consistent across `Info.plist`, `BackgroundSyncScheduling.swift` and specs/009 §3.4, and BGTask identifiers need not match the bundle id — cosmetic, not a defect. Changing it needs a spec change and must stay in lockstep with `Info.plist`, or `BGTaskScheduler.submit()` throws `notPermitted`.
