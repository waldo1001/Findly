# Store submission pack — every console answer, paste-ready

Written 2026-08-06, for the push from **M1 (family install)** to **M2 (public production listings)**.
Everything below is derived from the specs, the live privacy policy (`/privacy`) and the shipped
manifests — so the two stores' answers agree with each other *and* with the app. Answering these
consistently is not bureaucracy: **Apple and Google cross-check the two forms against the privacy
policy**, and a mismatch is one of the commonest rejection causes for location apps.

Companion docs: [`finish-line-runbook.md`](finish-line-runbook.md) (ordering), [`store-readiness.md`](store-readiness.md)
(why each gate exists), [`h6-apple-portal-runbook.md`](h6-apple-portal-runbook.md) (Apple portal, values pre-filled).

---

## 0. Read this before submitting: production makes the fix loop *slower*, not faster

The stated goal is "push a fix and it installs automatically." **That already works today** and does
not need production listings:

| Channel | Status now | Time from `git push` to installed on a family phone |
|---|---|---|
| Play **internal testing** | live, build 6 | upload → **minutes**, no review, auto-updates like any Play app |
| **TestFlight** (internal testers) | live, build 6 (`1d0d5839`) | upload → ~10 min processing, **no beta review** for internal testers |
| Play **production** | not submitted | upload → **hours to days of review**, every single update |
| **App Store** production | not submitted | upload → App Review, **hours to ~2 days**, every single update |

So production is worth doing for **reach** (strangers can install it — which specs/005 and 007's
convention use case actually requires), not for iteration speed. Keep internal testing / TestFlight as
the fast lane *after* going live; that is what those tracks are for.

**The thing that is genuinely broken today** is the sideloaded APK two family members are running
(`android-v1.0.0-build6` GitHub release): it is signed with the upload key, so Play can never upgrade it
in place, and it will silently diverge from the store build. Fixing that is 20 minutes, not weeks —
see §1.

---

## 1. First: close the actual pain (~20 min, no review involved)

1. **Play Console → Testing → Internal testing → Testers** — add every family Google account, copy the
   opt-in link, send it. They accept, install from Play. From then on updates land automatically.
2. **Tell the sideloaded testers to uninstall the APK first.** The signature differs from Play's app
   signing key, so an in-place upgrade is impossible — they must remove it before installing from Play.
3. Once at least one family member confirms the Play install works: `gh release delete android-v1.0.0-build6 --yes`
   (finish-line-runbook E0 — a public, un-updatable download on a public repo).
4. **App Store Connect → TestFlight → Internal Testing** — add the family's Apple IDs to the internal
   group. Internal testers need no beta review. Tell each of them to open TestFlight →
   Findly → **enable "Automatic Updates"** (it is per-app and worth turning on; it is what makes
   TestFlight behave like the Store).

That is M1 fully reached on both platforms. Everything below is M2.

---

## 2. Google Play — production submission

### 2.1 Store listing

| Field | Value |
|---|---|
| App name (30) | `Findly - Friends Locator` |
| Short description (80) | `See where your family is, on a private map only your family can read.` |
| App category | Lifestyle (alt: Maps & Navigation) |
| Tags | family, location sharing, gps |
| Contact email | `Findly@dynex.be` |
| Privacy policy URL | `https://kind-plant-0fb99b003.7.azurestaticapps.net/privacy` |
| Website (optional) | `https://kind-plant-0fb99b003.7.azurestaticapps.net/terms` |

**Full description** (paste as-is; deliberately does not promise iOS-style guaranteed intervals —
store-readiness §3 / 000 §O2):

```
Findly keeps a family in sight of each other, without handing your movements to an advertising company.

WHAT IT DOES
• Live map — every family member sees every other member's last known position, with a clear marker when a position is getting old.
• Your own interval — each device reports on the schedule you pick: every 5 or 10 minutes when you want freshness, every hour or once a day when you want battery. You choose per device, and you can pause any device entirely.
• Ask where someone is — tap a member and Findly wakes their phone for a fresh, accurate fix, whatever their normal interval is.
• Places — mark Home, School or Work and everyone gets a notification when someone arrives or leaves. Arrivals are detected by the phone itself, which is why it costs almost no battery.
• History — scroll back through where a device has been, on a map and a timeline.
• Temporary groups — going to a festival, a trip or a school outing with people who are not family? Create a group with an end date, share the code, and everyone sees each other on a map until it ends. Group members see live position only — never your history, your devices or your battery — and group locations are deleted automatically when the group is over.

PRIVACY, CONCRETELY
• No advertising. No analytics SDKs. Your location is never sold and never used for ads.
• Your location is visible to your family — people you invited — and to members of any temporary group you chose to join. Nobody else.
• Sign in with your phone number and an SMS code. There is no password to lose.
• Export everything we hold about you, or delete your account outright, from inside the app or from our website — immediately, without emailing anyone.

BATTERY
Findly is built around the phone's own low-power location and geofencing services rather than keeping GPS running. Longer intervals use less battery; the app tells you what each setting costs.

Operated by Dynex bv, Belgium. Data stored in the EU (Azure West Europe).
```

**Graphics needed** (the one genuinely outstanding asset job):

| Asset | Spec | Source |
|---|---|---|
| App icon | 512×512 PNG, 32-bit, no alpha | `design/findly-icon/generated/` |
| Feature graphic | 1024×500 PNG/JPG, no alpha | to produce |
| Phone screenshots | 2–8, min 1080px on the short side, 16:9 or 9:16 | capture from the `findly-test` AVD |
| 7" / 10" tablet | optional, but improves listing quality score | skip for v1 |

Screenshot set worth capturing: family map · a member's history trail · places/geofence list ·
device settings with the interval picker · a temporary group map.

### 2.2 Data safety form — the exact answers

Does the app collect or share user data: **Yes**. Is all data encrypted in transit: **Yes**.
Do you provide a way to delete data: **Yes** →
`https://kind-plant-0fb99b003.7.azurestaticapps.net/delete-account`

| Data type | Collected | Shared | Ephemeral? | Required? | Purposes |
|---|---|---|---|---|---|
| Location → **Approximate location** | Yes | **Yes** (other app users) | No | Required | App functionality |
| Location → **Precise location** | Yes | **Yes** (other app users) | No | Required | App functionality |
| Personal info → **Phone number** | **Yes** | No | No | Required | **Account management** (only) |
| Personal info → **Name** | Yes | Yes (other app users) | No | Required | App functionality |
| App info → **Device or other IDs** | Yes | No | No | Required | App functionality |

Notes that matter:

- **"Shared" means "shared with other app users"** here, and Play's definition includes exactly that.
  Answering "not shared" because there is no third party would be false and is a known rejection trigger
  for location apps.
- **Phone number is collected**, even though our backend never stores it — Firebase Auth (Google) does,
  on our behalf, inside our app. Play counts SDKs bundled in the app as collection by the app. The live
  privacy policy already says this, so the answers agree.
- **Device IDs**: the client-generated device UUID plus the FCM registration token (Firebase
  Installations). Both are stored server-side and tied to the account.
- **No** analytics, crash logs, ads, contacts, photos, messages, financial or health data. Verified in
  the dependency graph: `firebase-auth`, `firebase-messaging`, `play-services-location`, `maps-compose`,
  `zxing` — no Analytics, no Crashlytics, no ad SDK on either platform.
- Data is **not** used for advertising or marketing, **not** sold, and **not** transferred to third
  parties for their own purposes.

### 2.3 Background location declaration (the slow gate — budget review time)

Play Console → **Policy → App content → Location permissions**.

- Requests `ACCESS_BACKGROUND_LOCATION`: **Yes**
- Core feature that requires it: **"Family location sharing"** + **"Place arrival/departure alerts"**
- Is it core to the app's primary purpose: **Yes**

**Declaration text** (paste):

```
Findly is a family location-sharing app. Its single core purpose is that family members can see each
other's location on a shared map, and be notified when a family member arrives at or leaves a place
they have set up (home, school, work).

Both of these are inherently background features. A parent needs to know their child arrived at school
while the child's phone is in a bag with the screen off; if location were only collected while Findly is
in the foreground, the map would be empty for every member who is not actively looking at their own
phone, and arrival notifications — the feature people install this app for — could never fire at all.

Background location is used only to report the device's position to the family the user belongs to, on
an interval the user chooses per device (from every 5 minutes up to once per day), and to detect entry
and exit of geofences the user configured. It is never used for advertising, never sold, and never
shared outside the family or temporary group the user explicitly joined.

Before the runtime permission prompt is ever shown, the app displays a full-screen prominent disclosure
explaining what is collected, that it continues in the background, and who can see it, requiring an
explicit acknowledgement. Background location is then requested as a separate, later step — never
bundled with the initial foreground request. Users can pause any device's reporting at any time from
inside the app, and can delete their account and all stored location data immediately, in-app or on the
web.
```

**Demo video** — required, and it is the item most likely to be missing. Upload **unlisted to YouTube**
and paste the link. Record on the `findly-test` AVD or a real phone, ~60–90 s, no narration needed:

1. Fresh install (uninstall first — the disclosure only shows once per acknowledgement).
2. Launch → phone sign-in.
3. **Hold on the prominent disclosure screen for 5+ seconds so the reviewer can read every word.**
4. Tap Continue → the Android foreground location prompt appears → "While using the app".
5. Continue to the point where the **background** disclosure and the separate "Allow all the time"
   ask appear → grant.
6. Show the family map with a position, then the places screen and an arrival notification if you can
   trigger one.

The reviewer is checking one thing above all: **that our own explanation appears before the OS dialog,
not after.** That ordering exists in the code as of 2026-08-05 (Android commit `7283783`, iOS `ed8182c`)
— it did not before, and the earlier roadmap wrongly claimed it did.

### 2.4 App content — the rest

| Item | Answer |
|---|---|
| Target audience & content | **13+ only.** Do *not* tick any under-13 band |
| Is the app designed for children | **No** |
| Ads | **No ads** |
| Content rating questionnaire | Category: Utility/Productivity. Violence/sex/drugs/gambling: all **No**. **"Shares user's location with other users": Yes.** "User-to-user communication": Yes (display names visible to other group members). Expect PEGI 3 / ESRB Everyone with a "shares location" descriptor |
| Government app | No |
| Financial features | None |
| Health apps | No |
| Data deletion | In-app **and** the web URL above |
| News app | No |

**Why 13+ and not younger, deliberately:** children *use* Findly, but they never create their own
account — a parent sets up the family and adds them (privacy policy, "Children's accounts"). Declaring
an under-13 target audience pulls the app into Play's Families programme, whose requirements around
collecting personal data from children sit awkwardly with an app whose core function is precise
location. 13+ is both the honest answer for who signs up and the one that keeps the app out of a policy
regime it was never designed against. Revisit only with legal advice, not casually.

### 2.5 App access (review sign-in)

Findly is fully gated behind phone sign-in, so **you must give reviewers credentials or the review
fails on "we could not access the app"**.

- All functionality restricted: **Yes**
- Instructions:

```
Sign-in is by phone number + SMS code. Use the test number below; it does not send a real SMS and the
code is fixed:

  Phone number: <the +32 470 00 00 01 test number>
  Verification code: <the fixed 6-digit OTP>

After sign-in the app asks for a display name and offers to create a family — create one with any name
to reach the main map. Location will show as unavailable in an emulator without a mock position; set a
mock location to see a marker.
```

> ⚠️ The number and OTP live **only in the Firebase and Play consoles** — never commit them here
> (specs/006 §6.4, security-review-checklist §1). Fill them in when you paste.

---

## 3. Apple App Store — production submission

Steps 1–7 of [`h6-apple-portal-runbook.md`](h6-apple-portal-runbook.md) are done: App IDs, App Store
Connect record (Apple ID `6797994768`), APNs key `MS22L459T9`, signing, uploads via
`mobile/ios/scripts/release-testflight.sh`. What follows is the submission itself.

### 3.1 App information

| Field | Value |
|---|---|
| Name (30) | `Findly - Friends Locator` |
| Subtitle (30) | `Family location sharing` |
| Primary category | Lifestyle · Secondary: Navigation |
| Privacy policy URL | `https://kind-plant-0fb99b003.7.azurestaticapps.net/privacy` |
| Support URL | `https://kind-plant-0fb99b003.7.azurestaticapps.net/terms` |
| Copyright | `2026 Dynex bv` |
| Age rating | **4+**. Do **not** enable "Made for Kids" / the Kids Category |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` is already in `Info.plist` — nothing to answer |

**Promotional text** (170, changeable without review — use it for "what's new" style notes):

```
See your family on one private map. Choose how often each phone reports, get an alert when someone gets home, and delete everything you've ever shared in one tap.
```

**Description**: reuse §2.1's full description verbatim, minus the last line about Play. Consistency
between the two listings is worth more than bespoke copy.

**Keywords** (100 chars, comma-separated, no spaces):

```
family,locator,location,sharing,gps,tracker,kids,map,geofence,find,phone,safety
```

**Screenshots**: 6.9" iPhone required (1320×2868 or 1290×2796); 6.5" recommended. Same five shots as
Play. Capture in the Simulator (`Cmd+S`) — do **not** paste an emulator screenshot with Android chrome.

### 3.2 Privacy nutrition labels — must mirror §2.2 exactly

| Data type | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Location → **Precise Location** | Yes | **Yes** | **No** | App Functionality |
| Contact Info → **Phone Number** | Yes | Yes | No | App Functionality |
| Contact Info → **Name** | Yes | Yes | No | App Functionality |
| Identifiers → **User ID** | Yes | Yes | No | App Functionality |
| Identifiers → **Device ID** | Yes | Yes | No | App Functionality |

- **"Used for tracking" is No everywhere** — we never link this data to third-party data for ads.
  Consequently the app needs **no** App Tracking Transparency prompt and no `NSUserTrackingUsageDescription`.
- Nothing under Usage Data, Diagnostics, Purchases, Contacts, Search History, Sensitive Info.
- Apple's labels have no "shared with other users" axis the way Play's do; the sharing is described in
  the listing and the privacy policy instead. Do not misread that as "so answer 'not collected'".

### 3.3 Purpose strings — already shipped, verify they still read honestly

From `mobile/ios/Findly/Info.plist`:

- `NSLocationWhenInUseUsageDescription` — "Findly shows your family members' locations on a shared map.
  Your device's location is shared with your family while the app is open."
- `NSLocationAlwaysAndWhenInUseUsageDescription` — "Findly periodically shares your location with your
  family in the background, on the interval you choose in Settings, so everyone can see where everyone
  is even when the app isn't open."

Both name the sharing and the background behaviour explicitly, which is exactly what App Review checks
for a `location` background mode. No change needed.

`UIBackgroundModes` declares `location`, `remote-notification`, `fetch`, `processing` — all four are
genuinely used (009 §1–§5). Reviewers do ask about unused background modes; these are defensible.

### 3.4 App Review notes

```
Findly is a private family location-sharing app. All functionality is behind phone-number sign-in.

TEST ACCOUNT
Sign-in uses a phone number and an SMS code. Please use this test number, which does not send a real
SMS and accepts a fixed code:

  Phone number: <the +32 470 00 00 01 test number>
  Verification code: <the fixed 6-digit OTP>

After signing in, enter any display name and create a family with any name to reach the main map.

BACKGROUND LOCATION
The app declares the 'location' background mode because its core purpose is that family members see
each other's position on a shared map, and are notified when someone arrives at or leaves a place they
configured. Position reporting runs on a per-device interval the user selects (5 minutes to 1 day) and
can be paused per device at any time. A full-screen explanation is shown, and must be acknowledged,
before any location permission is requested.

PUSH
Push notifications are used for place arrival/departure alerts and to wake a device when a family
member asks for its current position. In the Simulator, push is not delivered; on a device it requires
the test family to have more than one member.

DATA DELETION
The account and all its data can be deleted from inside the app (Settings → Privacy & data), or on the
web at https://kind-plant-0fb99b003.7.azurestaticapps.net/delete-account
```

### 3.5 Also worth doing while you are in the portal

- **Register iOS App Check (App Attest)** — not required to submit, but it is the last precondition for
  H8 (opening SMS regions), and you are already logged in.
- The **Location Push entitlement** request (000 §O1) is submitted and pending; it is not a release
  blocker — locate works best-effort without it.

---

## 4. Order of operations

```
§1  family onto Play internal + TestFlight, kill the sideload      ~20 min, today
 │
 ├─ Track C (finish-line-runbook): Firebase web app + authorized domain
 │     └─ makes /delete-account actually sign people in  ← Play REQUIRES this URL to work
 │
 ├─ screenshots + feature graphic  (the only real production work left)
 ├─ record the background-location disclosure video
 │
 ├─ Play:  listing → data safety → location declaration → content rating → app access
 │            └─ submit to production review  ⏳ days (the location declaration is the slow part)
 │
 └─ Apple: listing → nutrition labels → age rating → review notes
              └─ submit  ⏳ hours–2 days
```

**Do Track C before submitting to Play.** The data-safety form's deletion URL must be a page that
genuinely signs a user in and deletes them; it currently loads (200) but Firebase web sign-in needs the
web app registered and the SWA host on the authorized-domains list. A reviewer who clicks it and cannot
sign in fails the submission on a policy item, not a bug.

## 5. Account reset — the one thing that is awkward to undo

Before real family onboarding (and certainly before production): delete every Firebase test user in
`findly-71f7b` and wipe test rows/blobs from `stfindly` (specs/006 §8, finish-line-runbook Track D).
Once real location history interleaves with test data, separating them is manual work.

**Keep the store-review test number** — it is a Firebase *test* number, configured in the console rather
than a real signed-up user, so the reset does not remove it. Both reviewers depend on it.
