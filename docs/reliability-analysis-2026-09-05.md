# Reliability analysis — "users are idle a lot" and "locate almost always fails"

_2026-09-05. Desk analysis of `main` (`6acf033`): specs 000/001/009, backend locate + push code, and the full Android/iOS device runtime. No device logs were available; every finding below cites the line that produces it, and §5 says how to confirm each one in the field._

## 0. TL;DR

Both symptoms have the same root: **the app was deliberately built to never keep itself alive in the background** (009 §1.1 "no continuous stream", WorkManager for ≥15 min, silent pushes on iOS), and on top of that stance there are **seven concrete defects** that make the little background time the OS does grant mostly wasted. The two symptoms are not independent: a device that is asleep is also the device that cannot answer a locate.

| # | Finding | Platform | Effect | Fix size |
|---|---|---|---|---|
| F1 | `requestLocation()` runs without `allowsBackgroundLocationUpdates = true` | iOS | every background capture (BG refresh **and** locate push) times out after 30 s | 1 line + spec note |
| F2 | The BG-refresh expiration handler never calls `setTaskCompleted` | iOS | iOS cuts the app's refresh budget over time → fewer wakes | 1 line |
| F3 | Locate is a data-only high-priority FCM message that never shows a notification | Android | FCM demotes the app's high-priority pushes to normal priority after 7 days → delivered in Doze maintenance windows, minutes to hours late | backend + client |
| F4 | `onMessageReceived` blocks up to 30 s + HTTP inside a 10 s FCM window; capture is a plain `getCurrentLocation` from a background process | Android | locate handler is killed or gets no fix | client (FGS) |
| F5 | Locate expires after **60 s**; a late fulfil stores the fix but the poll never shows it | backend | requester sees "expired" even when the phone answered at 70 s | backend + spec |
| F6 | Foreground service restarted by `START_STICKY` gets a null intent and never starts its loop | Android | 5/10-min devices become a zombie notification after any OS kill | 5 lines |
| F7 | Opening the app on Android never captures or flushes anything | Android | a person actively using the app still shows stale | small |

Plus the structural one: **F0 — WorkManager in Doze and BG-refresh on iOS are opportunistic by design**, so "idle" is what the spec currently promises. Fixing F1–F7 makes the app behave as specified; making it *persistent* needs a 009 amendment (§3 below) — that is a product decision (battery vs freshness) only you can take, and I recommend taking it.

## 1. Why users look idle

"Idle" on the map is `isStale = now − recordedAt > 2 × syncIntervalMinutes` ([latestLocations.ts:78](../backend/src/domain/location/latestLocations.ts)). For a 15-min device that is 30 minutes. Below is everything that stops a fix from arriving within 30 minutes.

### 1.1 iOS

**F1 — background captures cannot succeed (high confidence).** `SystemLocationProvider` creates its `CLLocationManager` at [LocationProviding.swift:113](../mobile/ios/FindlyKit/Sources/FindlyKit/LocationSensing/LocationProviding.swift) and never sets `allowsBackgroundLocationUpdates`. Since iOS 9 that property defaults to `false`, and with `false` CoreLocation does not deliver standard-service updates (which `requestLocation()` at line 206 uses) while the app is in the background, even though `UIBackgroundModes` contains `location`. So:

- every `BGAppRefreshTask` run → `syncRunner.runOnce()` → `captureAndQueue(.periodic)` → `requestLocation()` → **30 s timeout, no fix**;
- every `LOCATE_REQUEST` silent push → same path with `.locate` → **no fix**.

The only iOS captures that currently work are (a) foreground use, and (b) significant-location-change callbacks, which pass the OS-supplied location as a `hint` and skip `requestLocation()` entirely. SLC fires on ~500 m cell-tower changes, so a stationary phone (home, school) produces nothing for hours. That matches "idle a lot" exactly.

Fix: set `allowsBackgroundLocationUpdates = true` (guarded by `authorizedAlways`; setting it without the `location` background mode crashes, but the mode is declared) and `showsBackgroundLocationIndicator = false` (no blue pill for one-shot fixes). Spec: add to 004 §7 / 009 §3.4.

**F2 — the app is being penalised for over-running BG refresh.** [BackgroundSyncScheduling.swift:87–88](../mobile/ios/FindlyKit/Sources/FindlyKit/LocationSensing/BackgroundSyncScheduling.swift) cancels the work on expiration but never calls `setTaskCompleted(success:false)`. Apple's contract is that the handler marks the task complete; not doing so gets the app terminated and its future refresh scheduling reduced. Combined with F1 (every run takes the full 30 s), the app looks like a misbehaving background citizen and iOS schedules it less and less.

**F1b — SLC is started with only When-In-Use.** `startBackgroundMonitoring` at [LocationProviding.swift:222](../mobile/ios/FindlyKit/Sources/FindlyKit/LocationSensing/LocationProviding.swift) accepts `.whenInUse`. SLC only wakes a suspended/terminated app with **Always**. Harmless, but it means the permission banner ("foreground only") is the only signal the user gets that they are invisible, and the app quietly behaves as if monitoring works.

**F0-iOS — BG refresh cadence is usage-driven.** For a kid who never opens the app, iOS grants refresh a few times a day at most. 009 §3.4 accepts this. The cure is §3.

### 1.2 Android

**F0-Android — WorkManager cannot beat Doze.** [LocationSyncScheduler.kt:54](../mobile/android/app/src/main/java/com/findly/android/queue/worker/LocationSyncScheduler.kt) enqueues a 15-min `PeriodicWorkRequest`. Once the screen is off and the phone is still, Doze defers all jobs to maintenance windows: roughly hourly at first, then every 2, 4, 6 hours. A 15-min device therefore shows stale for most of the night and for any stationary afternoon. On top of that, Samsung/Xiaomi/Oppo/Huawei "app sleeping" features stop WorkManager entirely for apps the user has not opened recently. The 5/10-min foreground-service path (§3.2) does not have this problem — which is why every shipping family-tracker uses a foreground service for all intervals.

**F7 — foreground use captures nothing.** `AppContainer.onAppForeground()` at [AppContainer.kt:341](../mobile/android/app/src/main/java/com/findly/android/AppContainer.kt) only polls settings. There is no `source: "manual"` caller anywhere in the Android tree (grep: zero call sites) and no `runOnce()` on foreground. iOS does run `syncRunner.runOnce()` on foreground ([LocationRuntimeContainer.swift](../mobile/ios/FindlyKit/Sources/FindlyKit/LocationSensing/LocationRuntimeContainer.swift) `onAppForeground`). So on Android, a person looking at the family map is themselves stale on everyone else's map. Cheap fix: run `locationSyncRunnerOrNull()?.runOnce()` on every foreground (it also flushes whatever the queue accumulated).

**F6 — zombie foreground service.** `LocationForegroundService.onStartCommand` reads the interval from the intent at [LocationForegroundService.kt:48](../mobile/android/app/src/main/java/com/findly/android/queue/worker/LocationForegroundService.kt) and returns `START_STICKY` (line 57). When the OS kills and restarts a sticky service it passes a **null** intent → `syncIntervalMinutes == null` → the loop is never launched, but `startForeground` already ran. Result: "Findly is sharing your location" stays in the shade while nothing is captured, until the app is next opened *and* the interval changes (only `SettingsChangeDecision` rebuilds the schedule, and it no-ops when nothing changed). Fix: read the interval from `deviceSettingsStateStore` when the intent is null; also make `reschedule()` idempotent-restart on cold start.

**No boot receiver.** Nothing restarts the 5/10-min service after a reboot (WorkManager has its own boot receiver; the service does not). Add `RECEIVE_BOOT_COMPLETED` + a receiver that calls `scheduler.reschedule(current interval)` — starting a location FGS from `BOOT_COMPLETED` is an explicit Android 12+ exemption.

**Capture quality in the background.** [FusedLocationCapturer.kt:36](../mobile/android/app/src/main/java/com/findly/android/location/FusedLocationCapturer.kt) calls the two-argument `getCurrentLocation(priority, token)`, which only returns a location computed in the last few seconds and returns `null` when the provider cannot compute one quickly (indoors, no recent Wi-Fi scan, Doze). Use a `CurrentLocationRequest` with `setMaxUpdateAgeMillis(2 min)` and `setDurationMillis(25 s)`, and fall back to `lastLocation` when it is younger than the sync interval. A two-minute-old position is exactly what 009 §1.1 says is acceptable ("honest history"), and it turns many silent `null`s into fixes.

**Permission gate is foreground-only.** The periodic pipeline checks `ACCESS_FINE_LOCATION` only ([AppContainer.kt:230/268](../mobile/android/app/src/main/java/com/findly/android/AppContainer.kt)); on Android 10+ a background process without `ACCESS_BACKGROUND_LOCATION` gets nothing from FusedLocation. Behaviour is spec-conformant (denial is never fatal, banner shown) but worth knowing when reading field data: a "While using" grant looks identical to Doze from the server.

## 2. Why locate almost always fails

Six independent links, each sufficient to fail the request. Today most requests hit several.

1. **Push delivery (Android) — F3.** [fcmV1Sender.ts:95](../backend/src/adapters/push/fcmV1Sender.ts) sends `android.priority: high` with `data` only. Firebase documents that high-priority messages must result in a visible notification; if FCM sees a 7-day pattern where they do not, it **demotes that app instance's messages to normal priority**, and app-standby buckets cap the number of non-notifying high-priority messages per day. Normal-priority messages are delivered in Doze maintenance windows. Every family phone that has been installed for a week is in this state. Symptom: the push arrives 10–60 min after the request, well past the 60 s expiry (the 10-min grace in the handler then also drops it).
2. **Push delivery (iOS) — known O1.** Silent `content-available` pushes are budgeted, coalesced, deferred under Low Power Mode, and **never delivered to a force-quit app**. This was accepted as "best-effort" in 000 §O1; in practice it is "rarely". The entitlement application is still pending ([Findly.entitlements:11](../mobile/ios/Findly/Findly.entitlements)).
3. **Handler execution (Android) — F4.** `FindlyMessagingService.onMessageReceived` uses `runBlocking` ([FindlyMessagingService.kt:37](../mobile/android/app/src/main/java/com/findly/android/push/FindlyMessagingService.kt)) around a capture whose timeout is 30 s plus an HTTP call. FCM gives `onMessageReceived` about 10 s; beyond that the process loses its Doze exemption and can be killed. The capture itself is a background `getCurrentLocation` (needs background permission, returns `null` easily — §1.2).
4. **Handler execution (iOS) — F1.** Even when the silent push arrives, `requestLocation()` returns nothing in the background, so the handler times out at 30 s, then calls the fetch completion handler after the OS's 30 s budget ([AppDelegate.swift:99–100](../mobile/ios/Findly/Push/AppDelegate.swift)). iOS counts that against the app too.
5. **The 60 s window — F5.** [createLocateRequest.ts:27](../backend/src/domain/locate/createLocateRequest.ts) sets `expiresAt = now + 60 s`. Cold GPS alone can take 20–30 s; add push latency and the window is unrealistic on both platforms. Worse: a fulfil at 61 s stores the fix in last-known/history but throws `LOCATE_REQUEST_EXPIRED` and never writes `fixJson` ([fulfillLocateRequest.ts:146–150](../backend/src/domain/locate/fulfillLocateRequest.ts)), so the requester's poll ([pollLocateRequest.ts:71](../backend/src/domain/locate/pollLocateRequest.ts)) reports `expired` with `fix: null`. The phone did answer; the UI says it did not.
6. **Target selection.** `mostRecentlySeen(pool)` ([createLocateRequest.ts:113](../backend/src/domain/locate/createLocateRequest.ts)) orders by `lastSeenAt`, which only `POST /devices` updates — `reportLocations.ts` never touches the device row. For a member with an old and a new phone the push can go to the phone in the drawer. Minor, but real for families that keep old devices signed in.

Also worth checking in App Insights: a transport failure inside `pushSender.send` (OAuth exchange, FCM 5xx) is not caught in `createLocateRequest`, so it surfaces as `500 INTERNAL_ERROR` to the requester rather than `pushFailed`.

## 3. What "persistent enough" would actually take (spec decision)

009 §1.1 says "Clients MUST NOT hold a continuous location stream for periodic reporting" and 000 makes battery a hard requirement. That rule is the direct cause of F0 on both platforms. The industry answer (Life360, Google Family Link, Apple Find My) is a **low-power continuous presence**, not periodic wake-ups:

| Platform | Mechanism | Battery | What it buys |
|---|---|---|---|
| Android | Foreground service (type `location`) for every interval ≤ 30 min, not only 5/10. Inside it, a timer capture on the configured cadence. Keep WorkManager only for 60/120/1440. | The notification is already Play-approved for 5/10; cost is the timer + one fix per interval — the same GPS burn as today, minus Doze. | Immune to Doze and to most OEM killers (a visible FGS is what OEM "sleeping" heuristics respect). Also fixes locate: the process is alive to receive the push. |
| Android | Prompt once for `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Play permits it for apps whose core function is affected — this app qualifies) with a link to dontkillmyapp.com for the worst OEMs. | none | Removes the standby-bucket demotion of high-priority pushes and the Doze deferral of alarms. |
| iOS | With **Always**: keep `startUpdatingLocation()` running at `kCLLocationAccuracyThreeKilometers` with a large `distanceFilter`, `pausesLocationUpdatesAutomatically = false`, `allowsBackgroundLocationUpdates = true`; capture a balanced fix on a timer while alive. Add `startMonitoringVisits()` as a second cheap wake. | Kilometre accuracy is cell-tower only — Apple's own guidance for "always-on" apps; typically 1–3 %/day. | The app stays resident, so timers fire on cadence *and* the silent locate push finds a running process. This is how Find My Friends-class apps stay live without the location-push entitlement. |

I recommend amending 009: replace the "no continuous stream" MUST with "no continuous **high-accuracy** stream; a low-power presence stream (kilometre/cell accuracy on iOS, foreground service on Android) is required for intervals ≤ 30 min". Keep the 60/120/1440 intervals on today's opportunistic path so the battery-first option still exists for users who want it. `isStale` then becomes meaningful again instead of being true most of the day.

## 4. Recommended plan (ordered by payoff ÷ effort)

**Wave 1 — bug fixes, no spec change (each is a dev-loop task):**

- **I50** iOS: `allowsBackgroundLocationUpdates = true` when Always, `showsBackgroundLocationIndicator = false`; call `setTaskCompleted(success:false)` in the BG-refresh expiration handler; start SLC only with Always. (F1, F2, F1b)
- **A38** Android: run `runOnce()` on app foreground; foreground service recovers its interval from the state store on null intent; `BOOT_COMPLETED` receiver re-applies the schedule; `CurrentLocationRequest` with max-age/duration + `lastLocation` fallback. (F7, F6, capture quality)
- **B25** backend: raise locate expiry to 180 s (spec 001 §6.1) and make a fulfil that arrives within `expiresAt + 10 min` still write `fixJson` and return `fulfilled` (status `fulfilled`, optional `late: true`); update `lastSeenAt` from `POST /locations` and `/fulfill`; catch `pushSender` transport errors → `pushFailed`, never 500. (F5, target selection)

**Wave 2 — locate redesign (spec 001 §8.1 + 009 §5.1 amendment first):**

- **B26** backend: `LOCATE_REQUEST` becomes notification + data on Android ("Eric is locating you" — honest, keeps the high-priority quota healthy; `android.notification.channel_id` low importance). iOS payload unchanged until O1 lands.
- **A39** Android: on `LOCATE_REQUEST`, check `message.priority == HIGH`, start a short-lived location foreground service (FCM high-priority is an explicit start-from-background exemption; with `ACCESS_BACKGROUND_LOCATION` the service may read location), capture, fulfil, stop. `onMessageReceived` returns immediately. Without background permission fall back to the current in-process attempt.
- **Client UX (both):** poll for the full window (up to 180 s) and, on `expired`, do one `GET /locations/latest` before declaring failure — a late fulfil already updated last-known.

**Wave 3 — persistence (009 amendment §3 above, then A40 / I51).** This is the one that changes "idle a lot" into "live", and it is also what makes Wave 2 reliable on iOS without the entitlement.

**Wave 4 — iOS Location Push Service Extension (O1).** Apply for `com.apple.developer.location.push` now (Apple takes weeks); when granted: register `locationPushToken`, add the extension target, backend sends direct APNs (`apns-push-type: location`, `.p8` key). Only then does iOS locate become deterministic for a terminated app.

## 5. How to confirm before building

- **Server-side, one query:** in App Insights, count `POST /locations` per device per hour and `POST /locate-requests/{id}/fulfill` vs created. Expect iOS devices to show fixes only when foregrounded/moved (F1) and Android ones to show a 15-min cadence collapsing to 1–6 h at night (F0). Fulfil count vs created gives the true locate success rate; `fulfill` calls returning 410 confirm F5.
- **iOS F1 in five minutes:** on a TestFlight phone with Always granted, Console.app filter `subsystem:com.findly.ios`; background the app, send a locate; you will see the 30 s timeout with no `didUpdateLocations`. Flip `allowsBackgroundLocationUpdates` in a debug build and repeat.
- **Android F3:** `adb shell dumpsys deviceidle` + `adb shell cmd appops get com.findly.android` shows the standby bucket; a bucket of `rare`/`restricted` means high-priority pushes are already demoted. Also `RemoteMessage.getPriority()` vs `getOriginalPriority()` in the handler logs a demotion directly.
- **Android F6:** enable Developer options → "Don't keep activities"/background process limit, kill the process while on a 5-min interval; the notification returns, no fixes follow.

## 6. Things I did not change

No code or spec was edited: Wave 1 is spec-compatible, but this repo's process is a failing test first and a review gate per task, so the rows above are written to be dropped into `docs/implementation-handoff.md` as backlog entries. Wave 2 and 3 require spec commits before any code.
