# H6 — Apple portal runbook (step-by-step)

> Companion to [`docs/store-readiness.md`](store-readiness.md) §2. That section is the *checklist*; this is the *procedure*, with the concrete values from this repo filled in and a verification step for every item.
>
> **Status when written (2026-08-04):** enrollment is COMPLETE — Team ID **`92A2K3Q7NH`**, verified live in the served AASA. Nothing here is enrollment-gated. I9 (the `.xcodeproj`) and I15 (the Notification Service Extension) are both merged, so a build can actually be produced and uploaded.

## Values you will need

| Thing | Value | Source |
|---|---|---|
| Team ID | `92A2K3Q7NH` | verified in the live AASA |
| App bundle id | `com.findly.ios` | `mobile/ios/project.yml` |
| **Extension bundle id** | `com.findly.ios.NotificationService` | `mobile/ios/project.yml` (**new — added by I15**) |
| Associated domain | `applinks:kind-plant-0fb99b003.7.azurestaticapps.net` | `mobile/ios/Findly/Findly.entitlements` |
| Firebase project | `findly-71f7b` | rename runbook |
| BGTask identifier | `be.dynex.findly.refresh` | specs/009 §3.4 — normative, do not "fix" the old reverse-domain casually |

## Order matters — do step 1 first

Step 1 has an **independent Apple review queue** that nothing else depends on. Start it before the mechanical portal work so the wait overlaps with everything else.

---

## 1. Apply for the Location Push Service Extension entitlement

**Why:** specs/000 §O1. Silent pushes (`content-available: 1`) are budgeted and coalesced by iOS — they are not a reliable wake, so push-to-locate is best-effort on iOS today. `com.apple.developer.location.push` is the mechanism built for exactly this, and it requires an application to Apple with an unknown lead time.

**The form:** <https://developer.apple.com/contact/request/location-push-service-extension/>

It sits behind Apple developer sign-in (the bare URL 302s to `idmsa.apple.com`), and **must be submitted by the Account Holder** — not an Admin or Developer role. For this project that is you.

This is an **account-level enablement**, not a per-app one. Once Apple approves, `com.apple.developer.location.push` becomes available as a capability on your App IDs in Certificates, Identifiers & Profiles; you then enable it on `com.findly.ios`. Apple's own documentation is explicit that you request it **before** implementing the extension.

**Draft justification** — adapt, don't paste blind; it should read as your words:

> Findly is a private family location-sharing app. A parent can request an on-demand location update for a family member's device that has explicitly consented to sharing (each device opts in, and the owner can pause sharing at any time from the device itself).
>
> The app currently implements this with a silent background push (`content-available: 1`), which iOS budgets and coalesces — so a requested location update frequently does not arrive until the device happens to wake for another reason. This is the exact use case the Location Push Service Extension exists for: a power-efficient, on-demand location query when the app is not running.
>
> Location is only ever requested by a member of the same family group, is never shared outside it, and the app provides in-app export and deletion of all stored location history.

### 1a. Ordering correction — you need the App Store Connect record first

The form asks for **App Apple ID** and **App Store URL**. The Apple ID is the numeric identifier App Store Connect assigns when you *create the app record* — it does not exist until you do. So "step 1 first" is only true for the *queue*; you must do the first half of step 5 (create the ASC app record — no build upload needed, it's a two-minute form) before you can submit this one.

Revised order: **create the ASC record → submit this form → carry on with steps 2–4.**

### 1b. Field-by-field answers

| Field | Answer |
|---|---|
| **App name** | `Findly` |
| **Bundle ID** | `com.findly.ios` |
| **App Apple ID** | the numeric ID from the App Store Connect record (App Store Connect → your app → App Information → General Information) |
| **App Store URL** | The app is not released yet, so no public URL exists. State that plainly — e.g. *"Not yet released; app record created in App Store Connect, first build going to TestFlight."* Do not invent a URL. |

**Describe your app:**

> Findly is a private family location-sharing app. Members of a family (or a temporary, time-limited group) can see each other's locations on a shared map. Every device opts in explicitly, sharing intervals are chosen per device by the person who owns it, and any member can pause sharing from their own device at any time. Location data is only ever visible to members of the same family or group — it is never sold, shared with third parties, or used for advertising. The app provides full in-app export and deletion of stored location history.

**Describe how your app will make use of the Location Push Service Extension:**

> Only for the app's on-demand "locate" feature. When one family member requests a current location for another member's device, the app needs a single, high-accuracy fix from that device at that moment. Today this is implemented with a silent background push (`content-available: 1`), which iOS budgets and coalesces — the requested update often does not arrive until the device wakes for an unrelated reason, so the requester is left looking at a stale last-known position. The Location Push Service Extension is the mechanism designed for this: a power-efficient, on-demand location query when the app is not running. It returns one fix per request and is not used for continuous or background tracking — periodic location sharing uses ordinary background scheduling and significant-location-change monitoring, entirely separately from this extension.

**What will trigger a location push:**

> An explicit, user-initiated request. A family member taps "locate" on another member's device in the app; the backend sends exactly one location push to that specific target device. Nothing automated, scheduled, or geofence-driven ever triggers one. Requests expire after 60 seconds, and a concurrent request for a device that already has one pending is coalesced into the existing request rather than sending a second push.

**On average, how many location pushes will your app send a user per day:**

> Typically fewer than 5 per device per day, since each one requires a person to deliberately tap "locate". The backend enforces a hard ceiling of 100 locate requests per family per UTC day, shared across all members, and coalesces concurrent requests for the same device so repeat taps do not multiply pushes.

*(All four answers are grounded in the shipped implementation: `locateRequestsPerDay: 100` in `backend/src/domain/plan.ts`, coalescing and the 60-second expiry in specs/001 §6.1. Adapt the wording, but keep the numbers — they are enforced in code and should stay true.)*

**Set expectations honestly:** this is a request, not a switch. Response times vary from days to weeks, developers on Apple's forums report requests going unanswered, and Apple is selective — approval is not guaranteed. That is precisely why it goes first and why the app ships a working best-effort fallback (001 §8 payloads are designed for both paths, with "last known, updating…" UX). Nothing else in H6, or in shipping the app, depends on this being granted.

**Do NOT add the entitlement to `Findly.entitlements` before Apple grants it** — the file already carries a commented-out block saying exactly this, because adding an ungranted entitlement **breaks code signing**.

**When granted**, it is a follow-up task, not part of H6: locate pushes move to direct APNs (`apns-push-type: location`, topic `<bundleId>.location-query`), which adds an APNs `.p8` credential to the *backend* and a `locationPushToken` on device registration (001 §4.1, §8.1). FCM cannot address location push tokens. File it as its own spec'd task when the grant lands.

**Verify:** you have a confirmation/reference for the submitted request.

---

## 2. Register the two App IDs and their capabilities

Certificates, Identifiers & Profiles → Identifiers.

### 2a. `com.findly.ios` (should already exist)

Enable these capabilities:

| Capability | Why | Reference |
|---|---|---|
| **Push Notifications** | all FCM-routed push (001 §8) | specs/001 §8 |
| **Associated Domains** | public join links `https://…/g#CODE` | I6, specs/007 §3 |
| **App Attest** | App Check on iOS — blocks H8 | specs/006 §6.3 |

### 2b. `com.findly.ios.NotificationService` (**new — must be created**)

This did not exist before I15. An app extension needs its **own** App ID; a signed build fails without it.

- Create it as a plain App ID under the same team.
- **No capabilities needed.** I15's security review confirmed the extension declares no entitlements, no App Group, no Keychain, no network — it reads its own notification request and calls a pure function.

**Verify:** both identifiers appear in the portal; `com.findly.ios` shows all three capabilities enabled.

---

## 3. Create and upload the APNs auth key

**This is the highest-value step** — it unblocks two things that are otherwise stuck: iOS on-device phone sign-in (Firebase app verification needs it) and iOS App Check, which in turn blocks **H8**.

1. Keys → create a new key → enable **Apple Push Notifications service (APNs)**.
2. Download the `.p8`. **Apple lets you download it exactly once.** Store it in your password manager, not the repo.
3. Note the **Key ID** and your Team ID (`92A2K3Q7NH`).
4. Firebase console → project **`findly-71f7b`** → Project settings → Cloud Messaging → iOS app configuration → upload the `.p8` with its Key ID and Team ID.

**Never commit the `.p8`.** `docs/security-review-checklist.md` §1 forbids it and `.gitignore` already covers `*.p8`.

**Verify:** the Firebase Cloud Messaging tab shows the APNs key against the iOS app. Real verification is step 6.

---

## 4. Wire signing in the project

Both targets currently ship with `DEVELOPMENT_TEAM` commented out — deliberate, so simulator builds work without a team.

1. In `mobile/ios/project.yml`, uncomment `DEVELOPMENT_TEAM: 92A2K3Q7NH` for **both** the `Findly` and `FindlyNotificationService` targets (each has its own `TODO(H6)` marker).
2. Regenerate: `cd mobile/ios && xcodegen generate` — **never hand-edit `project.pbxproj`** (I9's rule; a reviewer verified the committed file is byte-identical to xcodegen output).
3. `aps-environment` is `development` in `Findly.entitlements`; Xcode switches it to `production` for distribution builds automatically. Leave it.

**Verify:** `xcodebuild build -scheme Findly -destination 'generic/platform=iOS Simulator'` still succeeds, and `git diff` shows only the intended `project.yml` + regenerated `project.pbxproj` changes.

---

## 5. App Store Connect app + TestFlight

1. App Store Connect → new app → platform iOS, bundle id `com.findly.ios`, name **Findly**.
2. Archive and upload a build from Xcode (Product → Archive → Distribute → App Store Connect).
3. Enable **TestFlight** internal testing and install on a real device.

**Privacy nutrition labels** — must match the Play data-safety answers already worked out for H5:
- Precise **location**, linked to identity, **shared with other users** (family/group members)
- **Phone number**, used for authentication
- Age rating appropriate for a family app

**App Review notes:** provide the test phone number sign-in approach, same as Play. Reviewers cannot receive a real SMS.

**Verify:** the build appears in TestFlight and installs on a device.

---

## 6. What to actually test on the device (this is the point)

A large amount of iOS work is written, unit-tested, and **never yet observed on real hardware**. TestFlight is what converts it. Test in this order:

1. **Phone sign-in** — needs step 3's APNs key. Fails without it.
2. **Push arrival** — `LOCATE_REQUEST`, `SETTINGS_CHANGED`, `GEOFENCE_CONFIG_CHANGED` (001 §8).
3. **`GEOFENCE_EVENT` re-rendering via the new extension (I15)** — this is the *only* way to verify it. `xcrun simctl push` provably never invokes a Notification Service Extension on Simulator (established empirically in I15 by both the implementing agent and its reviewer), and app-extension targets cannot be unit-tested directly. Trigger a real geofence transition and confirm the displayed notification is the client-rendered title, not the server's pre-baked one.
4. **Universal Links** — tap a `https://kind-plant-0fb99b003.7.azurestaticapps.net/g#CODE` link and confirm it opens the app rather than Safari.
5. **Background location** — the "Always" permission dance, and that fixes keep flowing with the app closed.

---

## 7. Then, and only then

- **H8** (go-open switch) needs App Check *enforced* on both platforms, which needs step 2a's App Attest plus step 3's key. H8 also waits on **H9** (the web App Check provider) — enforce before opening SMS regions, never the other way round.
- If Apple grants the Location Push entitlement (step 1), that becomes its own task.

## Notes

- **Nothing in this runbook belongs in the repo.** The `.p8`, provisioning profiles, and certificates are all password-manager material. The only repo change H6 produces is step 4's two-line `DEVELOPMENT_TEAM` uncomment plus the regenerated project file.
- The BGTask identifier `be.dynex.findly.refresh` keeps the pre-rename reverse-domain. It is consistent across `Info.plist`, `BackgroundSyncScheduling.swift`, and specs/009 §3.4, and BGTask identifiers need not match the bundle id — so it is cosmetic, not a defect. Changing it means a spec change first, and it must stay in lockstep with `Info.plist` or `BGTaskScheduler.submit()` throws `notPermitted`.
