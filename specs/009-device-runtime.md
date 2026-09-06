# 009 — Device runtime (capture, scheduling, push, geofencing)

## Goal

The normative on-device behavior that turns the built clients into an app that actually *tracks*: when a fix is captured, how it is scheduled on each platform, how the fix queue is persisted and flushed, how the four push types are handled, and how platform geofences are registered and reported. Everything here is **client runtime**; it defines no wire shape (those live only in [001](001-api-contract.md)) and no storage layout (only in [002](002-storage-schema.md)). Platform implementation detail lives in [003 §9–§11](003-android-client.md) / [004 §6–§7](004-ios-client.md), which reference this spec instead of duplicating it — the same split [006](006-phone-auth.md) uses for sign-in.

Battery is a **hard product requirement** (000 §Goal), so every rule here is written to minimize wakeups and GPS burn. Where a platform cannot honor a cadence, this spec says so explicitly rather than pretending (000 §O2).

> **Amended 2026-09-06 (000 §D19, `docs/reliability-analysis-2026-09-05.md`).** The first version of this spec forbade any continuous location session and relied on opportunistic wake-ups (WorkManager, `BGAppRefreshTask`, silent pushes). Field use showed that this makes every device read as stale for most of the day and makes push-to-locate fail almost always — a sleeping process cannot answer a push. This revision introduces a **low-power background presence** (§1.3) for intervals ≤ 30 min, fixes the platform mechanics that wasted the background time the OS did grant (§3.2 sticky restart, §3.4 `allowsBackgroundLocationUpdates`, BG-task completion), and re-specifies `LOCATE_REQUEST` handling (§5.1) around a user-visible push and a short-lived Android foreground service. Sections changed: §1.1, §1.3 (new), §1.4 (new), §3, §5.1, §7, §10, §12. Backlog: B26/B27, A39–A41, I50–I52, H11.

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively.

## 1. The pipeline (both platforms)

```
capture ──▶ durable queue ──▶ freeze batch ──▶ POST /locations ──▶ apply piggyback
  ▲                                                                     │
  └──────────── schedule (§3) ◀── deviceSettings / geofence ETag ◀───────┘
```

- **Capture** produces one fix (001 §5.1 shape) and appends it to the queue. Capture never uploads directly.
- The **durable queue** is the crash/offline boundary and MUST survive process death and reboot (§2).
- **Freeze/flush** rules (batch immutability, `batchId` reuse on retry, 4xx = dead batch) are already normative in 003 §10.2 / 004 §6 — this spec does not restate them.
- Every accepted response carries `deviceSettings` + `geofenceEtag` (001 §5.1); applying that piggyback (§3.5, §6.2) is **mandatory**, and is the primary way settings and geofence changes reach the device.

### 1.1 Fix sources and accuracy tiers (battery)

| `source` | Trigger | Accuracy request | Timeout |
|---|---|---|---|
| `periodic` | The schedule (§3) | **Balanced / ~100 m** — never continuous GPS | 30 s, then give up (no fix is better than a burned battery) |
| `locate` | `LOCATE_REQUEST` push (§5.1) | **High** (best available) | 30 s |
| `geofence` | A platform geofence transition (§6.3) | Balanced; MAY reuse the transition's own coordinates | 15 s |
| `manual` | User taps refresh in the app | High | 30 s |

Clients MUST NOT hold a continuous **high-accuracy** location stream for periodic reporting: every `periodic` fix is still a one-shot balanced request on a cadence. The only continuous session permitted is the §1.3 presence session, whose accuracy is deliberately too coarse to be a fix source on its own. A fix older than **2 minutes** at flush time MUST still be sent (it is honest history), but MUST NOT be re-captured to "freshen" it.

**Accepting a recent cached position (amended 2026-09-06).** A `periodic` or `geofence` capture MAY be satisfied by the platform's most recent already-computed location when it is **≤ 2 minutes** old (Android: `CurrentLocationRequest.setMaxUpdateAgeMillis(120 000)`; iOS: the `CLLocationManager.location` property when its `timestamp` is within 2 minutes). If the one-shot request fails or times out, a cached position **≤ `syncIntervalMinutes`** old MAY be queued instead (Android `lastLocation`; iOS `manager.location`) — a slightly old position on cadence is worth more to the family than a silent gap. `locate` and `manual` MUST NOT use either shortcut: they exist to produce a fresh fix. `recordedAt` MUST always be the position's own timestamp, never the capture time, so history stays honest.

### 1.2 Capture suppression

A capture MUST be skipped (not queued) when: tracking is paused (§4), location permission is absent or revoked (§7), or an identical-position fix was captured **< 60 s** ago (debounce against duplicate platform callbacks). Skipping is silent — never an error surfaced to the user.

### 1.3 Background presence (amended 2026-09-06 — 000 §D19)

For `syncIntervalMinutes` ∈ {5, 10, 15, 30} a device MUST keep a **low-power presence** while tracking is enabled and background-location permission is granted, so that (a) the cadence timer actually fires, and (b) the process is alive to receive a `LOCATE_REQUEST` push. Presence is a platform-specific mechanism whose battery cost is bounded by design, and it is **not** a fix source:

| Platform | Presence mechanism | Fix capture while present |
|---|---|---|
| Android | The §3.2 `FOREGROUND_SERVICE_LOCATION` service (persistent notification) | Its own timer at the configured cadence → one balanced one-shot request per tick (§1.1) |
| iOS | A standing `CLLocationManager` session at `kCLLocationAccuracyThreeKilometers`, `distanceFilter = 500 m`, `pausesLocationUpdatesAutomatically = false`, `allowsBackgroundLocationUpdates = true` (§3.4) | A timer at the configured cadence, running only while the app is resident → one balanced one-shot request per tick (§1.1); presence-session callbacks are additionally queued as `periodic` **hints** subject to §3.4's `× 0.8` rule |

Intervals **60, 120 and 1440** keep the original opportunistic path (WorkManager / `BGAppRefreshTask` + significant-location-change) with **no presence** — this is the battery-first option and MUST stay selectable. The Devices screen (010 §4) MUST label 5–30 as "live" and 60+ as "battery saver" so the trade-off is visible to the parent choosing it.

Presence MUST stop immediately on pause (§4), sign-out, permission revocation (§7), or a settings change to an interval ≥ 60; it MUST be (re)established on app cold start, on every foreground, on resume from pause, and — Android — after reboot (§3.2). Establishing presence is idempotent: calling it when already present is a no-op.

### 1.4 Foreground use is a trigger (amended 2026-09-06)

On **every** app foreground both platforms MUST run one full sync cycle (§3's `runOnce`: capture-if-due, flush fixes, flush geofence events, apply piggyback) in addition to the paused-device settings poll (§4). A person looking at the family map MUST never themselves be stale on the family's map because their own device only ever reported from the background. The foreground capture is `source: "periodic"` and subject to the §1.2 suppression and the §3.4 `× 0.8` elapsed rule; the explicit refresh control remains `source: "manual"`.

## 2. Durable queue (replaces the in-memory placeholders)

Both platforms shipped an in-memory queue behind an interface (003 §10.4 `FixQueueStore`, 004 §6 `FixStoring`) explicitly as a placeholder. A store-ready build MUST provide a **durable** implementation behind the *unchanged* interface: Android **Room**, iOS **Core Data or SQLite**.

Requirements: survives process death and reboot; preserves insertion order; persists the in-flight `PendingBatch` (`batchId` + frozen fix set) so a retry after a crash resends **identical** content (001 §5.1); atomic per operation; **capped at 1 000 fixes** — on overflow the **oldest** fixes are dropped first (a week-old position is worth less than a current one), and one drop event per flush cycle is logged at debug level with a count only (never coordinates).

## 3. Scheduling

`syncIntervalMinutes` ∈ {5, 10, 15, 30, 60, 120, 1440} (001 §1.4). The configured value is a **target**. For 5–30 the §1.3 presence makes delivery cadence-accurate whenever the OS lets the app stay resident (Android: always, once the foreground service runs; iOS: while the app is not force-quit and the phone is not in Low Power Mode); for 60+ delivery is opportunistic (000 §O2). `isStale` stays computed server-side (001 §5.2) so both cases render identically.

**Strategy selection (amended 2026-09-06):**

| `syncIntervalMinutes` | Android | iOS |
|---|---|---|
| 5, 10, 15, 30 | §3.2 foreground presence service | §3.4 standing low-power session + timer |
| 60, 120 | §3.1 WorkManager | §3.4 opportunistic triggers only |
| 1440 | §3.1 WorkManager + §3.3 once-per-day gate | §3.4 opportunistic triggers + once-per-day gate |

### 3.1 Android — 60 / 120 / 1440 minutes: WorkManager

A single **unique** `PeriodicWorkRequest` named `findly-location-sync`, enqueued with `ExistingPeriodicWorkPolicy.UPDATE`. Period = `syncIntervalMinutes`; flex interval = `min(5 min, period/3)`. Constraints: **none on network** — the worker captures a fix and queues it even offline; the upload leg tolerates failure and retries. Backoff: exponential, 30 s initial, on `Result.retry()`. The worker MUST be idempotent and complete in well under 10 minutes.

WorkManager runs only in Doze maintenance windows (hourly at best, then every 2–6 h) once the phone is still. That is acceptable for the battery-saver intervals and the reason 15/30 moved to §3.2 (amended 2026-09-06; previously ≥ 15 used WorkManager).

### 3.2 Android — 5 / 10 / 15 / 30 minutes: foreground presence service

A `FOREGROUND_SERVICE_LOCATION`-typed foreground service running a self-rescheduling timer at the configured cadence; each tick calls the same `runOnce` cycle the worker uses. It MUST be started only when `syncIntervalMinutes` ∈ {5, 10, 15, 30} **and** `ACCESS_BACKGROUND_LOCATION` is granted (an FGS started from the background may read location only with that permission — Android 11+), and MUST be stopped immediately when the interval rises to ≥ 60, tracking pauses, permission is revoked, or the user signs out. Without background permission the device falls back to §3.1 WorkManager for its interval (still opportunistic; the §7 banner explains why).

Its persistent notification is required by the OS and by Play policy for background location. Normative copy (000 §O8 — English in v1): title **"Findly is sharing your location"**, body **"Your family can see where you are."**, with the app's monochrome status icon (§8) and a tap action opening the app's Devices screen. The notification MUST NOT be silenced or disguised — Play treats that as a policy violation.

**Restart and recovery (amended 2026-09-06 — all MUST):**

- The service is `START_STICKY`. When the OS restarts it, `onStartCommand` receives a **null** `Intent`; the service MUST then read the interval from the cached `deviceSettings` (the same store §3.5 writes) and start its loop, never sit foregrounded with no loop. If the cache says paused, ≥ 60, or is empty, the service MUST `stopSelf()` — no zombie notification.
- The app MUST declare `RECEIVE_BOOT_COMPLETED` and a receiver for `ACTION_BOOT_COMPLETED` / `ACTION_MY_PACKAGE_REPLACED` that re-applies the current schedule (`reschedule(cachedInterval)`), which starts this service when the cached settings call for it (both broadcasts are explicit start-from-background exemptions). Geofence re-registration on the same events is already required by §6.2.
- Every app cold start and foreground MUST call `reschedule(cachedInterval)` idempotently (WorkManager's `UPDATE` policy and a redundant `startForegroundService` are both no-ops when nothing changed), so a service lost to any OEM kill is restored the next time the user opens the app at the latest.
- The service timer MUST use `AlarmManager.setAndAllowWhileIdle` (or an equivalent that survives Doze) rather than a coroutine `delay`, so a tick is not deferred to a maintenance window while the phone is still. **Honest limit (added 2026-09-06, A40 review):** `setAndAllowWhileIdle` is itself throttled by Doze to roughly **one delivery per app per 9 minutes** once the device is idle, so neither the 5-minute cadence nor §9's 30 s initial backoff fires on schedule while the phone is stationary and screen-off — both stretch to that floor. This is the accepted cost of the only Doze-permitted wake: an exact alarm (`SCHEDULE_EXACT_ALARM`) MUST NOT be requested to work around it, and clients MUST NOT assume a delivered tick means the configured cadence was honored. A device in this state still reports far more often than the pre-D19 WorkManager path, which is the point; `isStale` (001 §5.2) remains the honest signal to the family.

**Battery-optimisation exemption (amended 2026-09-06).** Once presence is required (interval ≤ 30 and background permission granted) the client MUST, once per install, explain and offer the `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt (Play permits it for apps whose core function is defeated by Doze; this app qualifies and the prominent disclosure of §7 already covers the why). Declining is not fatal: the service still runs; the app records the answer, never re-prompts automatically, and exposes a "Battery settings" action on the Devices screen. On OEMs known to kill foreground services (`Build.MANUFACTURER` ∈ a small maintained list: Xiaomi, Huawei, Oppo, OnePlus, Vivo, Samsung), the Devices screen MUST additionally link to the vendor-specific steps (dontkillmyapp.com). The exemption also lifts the app-standby-bucket cap on high-priority pushes (§5.1).

### 3.3 Android — 1440 (one day)

`PeriodicWorkRequest` with a 24-hour period is permitted, but the 000 §O3 semantics are what matter: **at least one fix per device-local calendar day, taken opportunistically**. The worker MUST check whether a fix already exists for the current local day and skip capture if so — never "24 h since the last fix".

### 3.4 iOS — all intervals

iOS cannot promise a fixed cadence to a suspended app, and this spec does not pretend otherwise (000 §O2). The runtime is the union of the opportunistic triggers below plus, for intervals ≤ 30, the §1.3 presence session that keeps the app resident so a cadence timer can fire. All of them capture-and-queue through the same pipeline.

**Opportunistic triggers (all intervals):**

1. **`BGAppRefreshTask`** (identifier `be.dynex.findly.refresh`), rescheduled at the end of every run — the system decides actual frequency from usage patterns. The registered handler MUST set an `expirationHandler` that cancels the work **and calls `setTaskCompleted(success: false)`**; a task left uncompleted is terminated by the system and counted against the app's future refresh budget (amended 2026-09-06 — the shipped handler cancelled without completing).
2. **Significant-location-change monitoring** (`startMonitoringSignificantLocationChanges`) — the battery-cheap always-on trigger; also relaunches the app after termination, which is why the queue must be durable (§2). It MUST be started only with **Always** authorization (When-In-Use cannot wake a suspended app; starting it earlier only misleads the permission banner logic — amended 2026-09-06).
3. **Visit monitoring** (`startMonitoringVisits`) — a second free wake on arrival/departure; treated exactly like an SLC callback (amended 2026-09-06).
4. **Geofence transitions** (§6) and **foreground** app use (§1.4).

**Presence session (intervals ≤ 30, Always authorization — amended 2026-09-06):** `startUpdatingLocation()` on the runtime's location manager configured with `desiredAccuracy = kCLLocationAccuracyThreeKilometers`, `distanceFilter = 500`, `pausesLocationUpdatesAutomatically = false`, `activityType = .other`, `allowsBackgroundLocationUpdates = true`, `showsBackgroundLocationIndicator = false`. At kilometre accuracy CoreLocation uses cell/Wi-Fi positioning only — no GPS — which is Apple's own guidance for always-on presence and costs on the order of 1–3 % battery per day. While the session runs, a repeating timer at `syncIntervalMinutes` performs the §1.1 one-shot balanced capture (`requestLocation()` at hundred-metre accuracy) and a `runOnce` cycle. Session callbacks are passed to the capture coordinator as `hint`s subject to the `× 0.8` rule so a moving phone gets on-cadence positions without an extra request.

**Background delivery of one-shot requests (all intervals — amended 2026-09-06, the root cause of every silent iOS background capture):** any `CLLocationManager` used for `requestLocation()` outside the foreground MUST have `allowsBackgroundLocationUpdates = true` set **whenever authorization is Always** (with `showsBackgroundLocationIndicator = false`). With the property at its default `false`, CoreLocation withholds standard-service updates while the app is in the background, so every BG-refresh and locate capture times out. The property MUST be reset to `false` if authorization drops below Always (setting it without the `location` background mode or the permission is a runtime error).

**Elapsed rule:** a capture is taken when a trigger fires **and** at least `syncIntervalMinutes × 0.8` has elapsed since the last queued fix (the 0.8 factor keeps a slightly-early system wake useful instead of wasted). Devices on 60+ intervals, and any device the user has force-quit, will legitimately report `isStale: true`; the UI presents the interval as a target (004 §7) and the Devices screen labels 5–30 as "live" (§1.3).

### 3.5 Reacting to settings changes

`deviceSettings` arrives by three paths — the §5.1 `SETTINGS_CHANGED` push (best-effort accelerator), the 001 §5.1 flush piggyback (active devices), and the paused-device poll (§4). On **any** path, if `syncIntervalMinutes` changed the schedule MUST be rebuilt immediately (re-enqueue with `UPDATE` / reschedule the BG task, and start or stop the presence service/session per §1.3 when the interval crosses the 30/60 boundary); if `trackingEnabled` changed, apply §4. Independently of change detection, cold start and foreground re-apply the cached schedule idempotently (§3.2 "Restart and recovery").

## 4. Pause (`trackingEnabled: false`)

001 §5.1 is normative; on-device this means, in order: stop the periodic worker / cancel the BG task, stop the §3.2 foreground service if running, **unregister all platform geofences** (§6), and stop capturing. Transitions detected while paused are **dropped**, not queued.

Fixes captured **before** the pause stay in the queue and MAY be uploaded after resume — they are honest history. A paused device MUST NOT flush (`POST /locations` would return `403 TRACKING_PAUSED`).

**Resume is pull-based, never push-dependent:** while paused the client MUST re-check settings via `GET /devices` on every app foreground **and at least every 6 hours** (a low-frequency worker/BG task is the only thing that keeps running while paused). On observing `trackingEnabled: true`, restore the schedule (§3) and re-register geofences (§6.2).

## 5. Push handling (001 §8)

The client MUST ignore unknown `data.type` values (001 §1.1 forward compatibility) — including the reserved group types of 001 §8.7. All `data` values arrive as strings and MUST be parsed defensively; a malformed payload is dropped silently, never crashed on.

### 5.1 `LOCATE_REQUEST` (amended 2026-09-06)

A **user-visible** high-priority push on both platforms (001 §8.1): the located person always sees "**{requestedByName} is locating you**". This is honest UX, and it is also what keeps delivery reliable — FCM demotes an app's high-priority messages to normal priority when they do not produce notifications, and iOS delivers an alert push (`apns-priority: 10`) where it budgets a silent one.

On receipt: if `now > expiresAt + 10 min`, **ignore it** (001 §6.3 — no GPS burn for a stale request). Otherwise capture one **high-accuracy** fix and `POST /locate-requests/{id}/fulfill` with `source: "locate"`. A paused device **still fulfills** (001 §6.3 — pause stops periodic surveillance, not an explicit request). Failure to obtain a fix within the §1.1 timeout: give up silently; the requester's poll surfaces the outcome. Because 001 §6.1 now allows 180 s and 001 §6.3 honours a fulfil up to 10 min late, a slow fix is still worth sending — the client MUST NOT abandon a capture merely because `expiresAt` has passed.

**Android execution model (MUST):** `onMessageReceived` has roughly 10 s of guaranteed execution and MUST return immediately after handing off; it MUST NOT block on the capture. The handoff is:

1. Read `RemoteMessage.priority`. If it is `PRIORITY_HIGH` (not demoted), start a **short-lived** `FOREGROUND_SERVICE_LOCATION` service — starting an FGS from a high-priority FCM message is an explicit Android 12+ exemption, and with `ACCESS_BACKGROUND_LOCATION` granted the service may read location. The service **posts the locate notification itself** (title rendered on-device from `data.requestedByName`: "{requestedByName} is locating you" — the Android message is data-only on purpose, because an FCM `notification` block would make the SDK display it and skip `onMessageReceived` for a backgrounded app), uses that notification as its foreground notification, captures the fix, fulfils, and stops itself. Hard cap: 45 s, then stop regardless.
2. If the message was demoted to normal priority, or background permission is absent, fall back to a **`WorkManager` expedited one-time request** (`setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)`) running the same capture-and-fulfil; it is best-effort and may be late, which the 10-minute grace tolerates. *(Constant corrected 2026-09-06 by A39's review: the spec previously named `RUN_AS_NON_EXPEDITED_WORK_REQUEST_FALLBACK`, which `androidx.work.OutOfQuotaPolicy` does not define — it has only `RUN_AS_NON_EXPEDITED_WORK_REQUEST` and `DROP_WORK_REQUEST`.)* **On API ≤ 30 WorkManager runs expedited work as a foreground service and calls `getForegroundInfoAsync()`**, whose default implementation throws — so the worker MUST override `getForegroundInfo()` and return the same locate notification, or this entire fallback is dead on Android 8–11, which is exactly the degraded-device population it exists for.
3. If the §1.3 presence service is already running, it MAY perform the capture directly (it is already a foregrounded location service) — no second service.

**All three branches MUST post the notification (clarified 2026-09-06 — A39's review).** The notification is not an artefact of the foreground-service branch; it is the promise made at the top of this section, and on Android it is the *only* thing that shows it, because 001 §8.1 keeps the Android message data-only precisely so the client renders the title itself. A branch that captures without posting produces a **silent locate** — the exact failure this amendment exists to remove — and, because FCM demotes apps whose high-priority messages produce no notification, a silent branch actively degrades delivery for every future locate. Implementations MUST therefore share one notifier across all three options: post before the capture, cancel in a `finally`; the foreground-service branch passes that same notification to `startForeground`, and the expedited-work branch passes it to `getForegroundInfo()`.

The locate notification channel is `findly_locate` (importance DEFAULT, sound per user setting); the notification MUST be dismissed automatically when the fulfil completes or the 45 s cap passes.

**Option 1 is a fallback chain, not a preference (clarified 2026-09-06).** If the foreground-service start is refused — `ForegroundServiceStartNotAllowedException` on a lost exemption, or a `SecurityException` when location permission was revoked between the handoff check and the start — the client MUST fall through to option 2 rather than dropping the request, and MUST NOT let either throw reach an unguarded coroutine scope. 001 §6.3's 10-minute grace tolerates the resulting delay.

**iOS execution model (MUST):** the push arrives as alert + `content-available` (001 §8.1). Whether the user taps it or not, `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` runs in the background with ~30 s; the handler MUST start the capture (which needs `allowsBackgroundLocationUpdates = true`, §3.4), wrap the work in `beginBackgroundTask` so the fulfil call can complete, and call the completion handler with `.newData` as soon as the fulfil request has been **sent** (not after the capture times out — a handler that overruns 30 s is penalised). A force-quit app receives the alert but not the callback; that case is only solved by the Location Push entitlement (000 §O1, §10). If the app is foregrounded when the push arrives, the handler runs the same path **and the alert is still presented** (`willPresent` returns `[.banner, .sound]` for this type, like every other).

**Corrected 2026-09-06 (I51's security review).** This sentence previously required the opposite — `willPresent` returning `[]` for `LOCATE_REQUEST` — which contradicted this section's own opening MUST ("the located person **always** sees …") and reproduced, on iOS, precisely the silent-locate failure the paragraph above condemns on Android. It was worse than the general case, because the suppressed window is the one where the person is holding and looking at the phone. Android has no equivalent carve-out: its notification is posted by the client and appears in the shade whether or not the app is open, so suppressing on iOS also broke cross-platform parity in the one guarantee this feature exists to provide. A banner over the app the user is already in is not noise here — it is the disclosure. Any future desire to soften the foreground case MUST replace it with an equally visible in-app signal, never with silence.

**Requester side (both clients, MUST):** poll every 2 s until a terminal status **or `expiresAt`**, then perform one `GET /locations/latest` and, if the target's `recordedAt` is newer than the request's `createdAt`, show that position as the answer (a late fulfil already updated last-known) before declaring the device unreachable. The UI states are `lastKnown → updating → (fresh | late | unreachable)` (010 handoff's four-state card, with `late` rendered exactly like `fresh` plus an age caption).

### 5.2 `SETTINGS_CHANGED`

Carries the complete current values of both fields (001 §8.3) — apply **both**, idempotently, per §3.5. Never treat it as a delta.

### 5.3 `GEOFENCE_EVENT`

A user-visible notification about **another** member. Clients MAY re-render the alert locally from `data` (000 §O8). No location action is taken.

### 5.4 `GEOFENCE_CONFIG_CHANGED`

`GET /geofences` with `If-None-Match` and, on a `200`, re-register platform geofences (§6.2).

### 5.5 Token lifecycle

The `PushTokenProvider` / equivalent contract is already fixed (003 §9): on every token refresh the client re-calls `POST /devices` with the new token (001 §4.1, 000 §O4). A store-ready build replaces the stub with the real FCM implementation behind that unchanged interface. The token MUST also be re-sent on first launch after sign-in and after every app update.

## 6. Geofencing

Geofences are evaluated **natively on-device** for battery (000 §5); the backend never computes them.

### 6.1 Source of truth

The synced config document (001 §7.1) — whole-document with an ETag, never per-fence CRUD (000 §D5). The client caches the document and its ETag.

### 6.2 Registration lifecycle

Register **all** configured geofences with the platform (`GeofencingClient` / `CLLocationManager` region monitoring), capped at `features.limits.maxGeofences` (20 — the iOS platform cap, 000 §O9). Re-registration is a **full replace** (unregister all, register all) and happens on: first config sync after sign-in, any observed ETag change (piggyback §1 or push §5.4), resume from pause (§4), and device reboot / app reinstall (both platforms lose registrations).

Devices MUST register and report **all** transitions regardless of the `notifyOnEnter`/`notifyOnExit` flags — those control server-side fan-out only (001 §7.1), and reporting everything keeps history complete and lets flag changes take effect with no device round-trip.

**Non-atomicity is accepted, not a bug to solve (normative).** "Unregister all, register all" is two separate platform calls on both `GeofencingClient` and `CLLocationManager`; neither platform makes the sequence atomic. If the process dies between them, the device is left with **zero** geofences registered — a real, reachable state, not a hypothetical. Implementations MUST NOT attempt to make this atomic (there is no platform primitive for it). The self-healing bound is the existing trigger set (§6.2): the very next location report's `geofenceEtag` piggyback (001 §5.1) — which fires on the device's own sync cadence, independent of geofencing — detects the mismatch and re-triggers a full re-registration. Worst case is a gap in geofence detection bounded by one sync interval, not indefinite silence.

### 6.3 Transition handling

On an enter/exit callback: build one event (001 §7.3 shape, client-generated UUIDv4 `eventId`) and queue it; **additionally capture one fix with `source: "geofence"`** so the map has a position matching the event (001 §5.1). Events are flushed like fixes, batched 1–20 per call, idempotent on `eventId`. If the response's `geofenceEtag` differs from the cached one, re-sync config (§6.2) — this is how a device with stale config self-heals after reporting an unknown `geofenceId` (001 §7.3).

**The durable geofence-event queue has no overflow cap, unlike the fix queue's 1 000-fix cap (§2) — deliberately, not an oversight.** A queued fix is a decaying position snapshot: past some backlog size, the oldest ones are no longer useful (the device will report a fresher position soon anyway), so dropping them is an acceptable, spec'd trade-off. A queued geofence event is a discrete accountability fact — "this device crossed this boundary at this instant" — with no equivalent decay; silently dropping one would produce a false negative in a family's activity history with no way to detect or recover it later, which is a materially worse failure than a stale position. Implementations MUST NOT impose an overflow cap on the geofence-event queue analogous to the fix queue's.

## 7. Permissions

Android staging is already normative in 003 §11 (fine → background as a separate later request, rationale first, `POST_NOTIFICATIONS` independently). iOS mirrors it: **When-In-Use first**, then a deliberate **Always** upgrade prompt shown only after an in-app explanation of family/group background tracking, plus a separate notification-authorization request (`UNUserNotificationCenter.requestAuthorization([.alert, .sound])`) — the latter MUST actually be issued on first sign-in (amended 2026-09-06: the shipped client never requested it, so no geofence or locate alert could ever display on iOS).

**Presence needs background permission (amended 2026-09-06).** Android's `ACCESS_BACKGROUND_LOCATION` and iOS's **Always** are prerequisites for §1.3 presence, for §3.4 background one-shot delivery, and for a background `LOCATE_REQUEST` capture. The §7 background disclosure copy MUST say so in one sentence ("Without 'Allow all the time' / 'Always', your family only sees you while Findly is open, and 'Locate now' cannot reach this phone"). The degraded-state banner for a When-In-Use-only device on an interval ≤ 30 MUST use the `FOREGROUND_ONLY` wording and route to the background disclosure. Android additionally stages the §3.2 battery-optimisation prompt **after** background permission is granted, never before or in the same session as the OS location prompt.

Both platforms: a **prominent disclosure precedes the OS prompt** (Play policy for background location; also the honest thing to do). Denial is never fatal — the app still shows others' locations; this device simply cannot report, and the client MUST surface a persistent, dismissible-per-session in-app banner explaining the degraded state with a route back to resolving it (the full-screen disclosure or system settings, whichever applies — see the A25 paragraph below for exactly which). Permission state MUST be re-checked on every app foreground (the user can revoke it at any time from system settings), and revocation while running stops capture without crashing.

**Full-screen disclosure re-presentation (A25).** The full-screen prominent disclosure above MUST auto-present only while it has never been answered. "Not now" counts as answered, exactly like acknowledging it: once a kind (foreground or background) has been answered, the client MUST NOT auto-re-present that full-screen disclosure on a later launch or foreground — re-showing an unanswerable interstitial on every cold start is the nagging pattern store review discourages and users uninstall over. The persistent degraded-state banner above remains the ongoing nudge for a device that still cannot report; an explicit user action on that banner MUST re-open the full-screen disclosure for the relevant kind, which then proceeds to the OS prompt or to system settings as appropriate (the OS prompt only if the platform permission itself has not already been irrevocably refused). Acknowledgement state and "answered" (declined) state are both part of the account-deletion local wipe (§4.4-equivalent client-side clearing) — a different user on the same device MUST see the disclosure again.

## 8. Notification icons

The Android status-bar icon MUST be the monochrome silhouette asset (`ic_stat_findly`, `design/findly-icon/`) — Android renders status icons as a mask, so any colored icon becomes a white blob. The `ic_stat_locating` variant is used for the §3.2 foreground-service notification. iOS uses the app icon (no separate asset).

## 9. Error handling & backoff

- Transient flush failures (network, 5xx) use exponential backoff — 30 s initial, doubling, **capped at the sync interval** (never back off past the next natural capture).
- `403 TRACKING_PAUSED` → apply §4 immediately using the `error.details.deviceSettings` echoed in the response.
- `401 AUTH_TOKEN_EXPIRED` → the existing refresh-and-retry-once path (001 §2.1); a second failure means signed-out, and the client stops the schedule.
- `404 DEVICE_NOT_FOUND` on a device-originated call means this registration is gone (deleted account, wiped family, re-installed) → stop the schedule, clear local device state, and re-run registration (001 §4.1); if that also fails, return to sign-in.
- **Never log coordinates, `deviceId`, phone numbers, or tokens** (`docs/security-review-checklist.md`). Counts and error codes only.
- **Untrusted display names in on-device notification text (added 2026-09-06 — A39's security review).** `data.requestedByName` (001 §8.1) is another user's `displayName`: server-validated for length (1–30) but **not** for character content. Before rendering it into any notification the client MUST strip bidi controls (U+202A–U+202E, U+2066–U+2069) and collapse newlines and other control characters, and SHOULD clamp to 30 characters as defence in depth. The locate notification is the feature's transparency guarantee — "you are being located right now" — so text that can be visually reversed or truncated defeats the control itself. This is a client-side obligation regardless of any server-side hardening.

## 10. Non-goals & deferred

- **iOS Location Push Service Extension** — the reliable locate wake for a **force-quit** app; gated on the Apple entitlement (000 §O1, backlog H11). v1 ships the alert + `content-available` push of §5.1 plus the §1.3 presence session, which together cover every state except force-quit; the `locationPushToken` plumbing exists in 001 §4.1 but stays dormant.
- **Cadence guarantees on iOS for a force-quit app or in Low Power Mode** — not achievable (000 §O2); the §1.3 presence session is the closest honest approximation and is explicitly best-effort in those two states.
- **Adaptive presence accuracy** (raising the presence session to hundred-metre accuracy while moving, dropping to kilometre when still) — a further battery/freshness refinement; deferred with the activity-recognition item below.
- **Per-group sharing pause** — 000 §O13; pause stays device-global (005 §3).
- **Activity-recognition / motion-adaptive cadence** — a real battery win, but it needs its own spec and permission story; deferred until field data from M1 (docs/store-release-roadmap.md) justifies it.
- **Client-side geofence evaluation above 20 regions** — 000 §O9.

## 11. Error cases

No new 001 §10 codes. The runtime consumes the existing catalog: `TRACKING_PAUSED`, `DEVICE_NOT_FOUND`, `AUTH_TOKEN_EXPIRED`, `VALIDATION_FAILED` (dead-batch handling, 003 §10.3 / 004 §6), `LOCATION_BATCH_TOO_LARGE` (prevented client-side by the 100-fix split rule), `LIMIT_EXCEEDED`.

## 12. Test checklist (conforming clients — pure-logic tests; no platform framework in unit tests)

- **Capture policy:** accuracy tier per `source`; suppression when paused / permission-absent / <60 s duplicate; a stale queued fix is sent, not re-captured; a ≤ 2-minute cached position satisfies `periodic`/`geofence` but never `locate`/`manual`; on one-shot failure a cached position ≤ interval old is queued with its own `recordedAt`, older ones are not.
- **Presence (§1.3):** interval → presence required (5–30 yes, 60+ no); established on cold start / foreground / resume / boot (Android), idempotent when already present; stopped on pause / sign-out / revocation / interval ≥ 60; the Devices screen labels 5–30 "live" and 60+ "battery saver".
- **Foreground trigger (§1.4):** every foreground runs one full `runOnce` cycle on both platforms, subject to suppression and the `× 0.8` rule.
- **Queue durability:** survives simulated process death with the in-flight `PendingBatch` intact (same `batchId`, identical fixes on retry); insertion order preserved; 1 000-fix cap drops **oldest** first and logs a count only.
- **Scheduling:** interval → strategy selection (5–30 presence service / 60–120 WorkManager / 1440 WorkManager + once-per-local-day with the same-day skip); rebuild on `syncIntervalMinutes` change from **all three** settings paths (push, piggyback, paused poll); foreground service starts and stops on exactly the specced conditions; **null-intent restart** reads the cached interval and starts the loop, or stops itself when the cache is paused/≥ 60/empty; boot and package-replaced broadcasts re-apply the cached schedule; the battery-optimisation prompt is offered once, only after background permission, and never auto-repeated.
- **iOS background delivery (§3.4):** `allowsBackgroundLocationUpdates` is `true` exactly when authorization is Always and `false` otherwise; SLC/visits start only with Always; the BG-refresh expiration handler completes the task with `success: false`.
- **Pause:** worker stopped, service stopped, presence stopped, geofences unregistered, transitions dropped, no flush attempted; pre-pause fixes retained; resume via the 6-hour/foreground poll restores schedule, presence **and** geofence registrations.
- **Push:** each `data.type` routed correctly; unknown and reserved types ignored; malformed payload dropped without crash; `LOCATE_REQUEST` past `expiresAt + 10 min` ignored, within the window fulfilled even while paused **and** even when `expiresAt` itself has passed; Android handoff picks FGS on `PRIORITY_HIGH` + background permission, expedited work otherwise, and `onMessageReceived` returns without awaiting the capture; **every** handoff branch posts and later dismisses the locate notification, and a refused FGS start falls through to expedited work instead of dropping the request; the notification title is sanitised against bidi/control characters before rendering (§9); iOS completion handler fires once the fulfil request is sent; requester polls to `expiresAt` then checks `/locations/latest` and renders `late` when last-known is newer than `createdAt`; `SETTINGS_CHANGED` applied as full state (both fields, idempotent, reorder-safe).
- **Geofencing:** full-replace re-registration on each §6.2 trigger; 20-region cap; all transitions reported regardless of notify flags; transition also queues a `source: "geofence"` fix; ETag mismatch in a response triggers re-sync.
- **Permissions:** staged request order; denial paths produce the banner state, not a crash; revocation mid-run stops capture **and presence**; re-check on foreground; iOS notification authorization is requested on first sign-in; a When-In-Use-only device on an interval ≤ 30 gets the `FOREGROUND_ONLY` banner routed to the background disclosure.
- **Backoff:** exponential, capped at the sync interval; `DEVICE_NOT_FOUND` triggers re-registration then sign-out.
- **Logging invariant:** no test fixture or log statement emits coordinates, `deviceId`, tokens, or phone numbers.

## Open questions

None — deferred runtime matters are tracked in 000 §Open Items (O1 location push, O2 cadence limits, O9 geofence cap, O13 per-group pause) with v1 behavior fixed by this spec. The 2026-09-06 presence decision is 000 §D19; its battery cost is to be measured in the field (backlog A41/I52 carry the measurement step) rather than left open here.
