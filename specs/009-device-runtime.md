# 009 — Device runtime (capture, scheduling, push, geofencing)

## Goal

The normative on-device behavior that turns the built clients into an app that actually *tracks*: when a fix is captured, how it is scheduled on each platform, how the fix queue is persisted and flushed, how the four push types are handled, and how platform geofences are registered and reported. Everything here is **client runtime**; it defines no wire shape (those live only in [001](001-api-contract.md)) and no storage layout (only in [002](002-storage-schema.md)). Platform implementation detail lives in [003 §9–§11](003-android-client.md) / [004 §6–§7](004-ios-client.md), which reference this spec instead of duplicating it — the same split [006](006-phone-auth.md) uses for sign-in.

Battery is a **hard product requirement** (000 §Goal), so every rule here is written to minimize wakeups and GPS burn. Where a platform cannot honor a cadence, this spec says so explicitly rather than pretending (000 §O2).

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

Clients MUST NOT hold a continuous location stream for periodic reporting. A fix older than **2 minutes** at flush time MUST still be sent (it is honest history), but MUST NOT be re-captured to "freshen" it.

### 1.2 Capture suppression

A capture MUST be skipped (not queued) when: tracking is paused (§4), location permission is absent or revoked (§7), or an identical-position fix was captured **< 60 s** ago (debounce against duplicate platform callbacks). Skipping is silent — never an error surfaced to the user.

## 2. Durable queue (replaces the in-memory placeholders)

Both platforms shipped an in-memory queue behind an interface (003 §10.4 `FixQueueStore`, 004 §6 `FixStoring`) explicitly as a placeholder. A store-ready build MUST provide a **durable** implementation behind the *unchanged* interface: Android **Room**, iOS **Core Data or SQLite**.

Requirements: survives process death and reboot; preserves insertion order; persists the in-flight `PendingBatch` (`batchId` + frozen fix set) so a retry after a crash resends **identical** content (001 §5.1); atomic per operation; **capped at 1 000 fixes** — on overflow the **oldest** fixes are dropped first (a week-old position is worth less than a current one), and one drop event per flush cycle is logged at debug level with a count only (never coordinates).

## 3. Scheduling

`syncIntervalMinutes` ∈ {5, 10, 15, 30, 60, 120, 1440} (001 §1.4). The configured value is a **target**; actual delivery is opportunistic on both platforms (000 §O2), which is why `isStale` is computed server-side (001 §5.2) rather than being a client concern.

### 3.1 Android — ≥ 15 minutes: WorkManager

A single **unique** `PeriodicWorkRequest` named `findly-location-sync`, enqueued with `ExistingPeriodicWorkPolicy.UPDATE`. Period = `syncIntervalMinutes`; flex interval = `min(5 min, period/3)`. Constraints: **none on network** — the worker captures a fix and queues it even offline; the upload leg tolerates failure and retries. Backoff: exponential, 30 s initial, on `Result.retry()`. The worker MUST be idempotent and complete in well under 10 minutes.

WorkManager's floor is 15 minutes; 5/10-minute targets therefore go to §3.2.

### 3.2 Android — 5 / 10 minutes: foreground service

A `FOREGROUND_SERVICE_LOCATION`-typed foreground service running a self-rescheduling timer at the configured cadence. It MUST be started only when `syncIntervalMinutes` ∈ {5, 10} **and** background-location permission is granted, and MUST be stopped immediately when the interval rises to ≥15, tracking pauses, or the user signs out.

Its persistent notification is required by the OS and by Play policy for background location. Normative copy (000 §O8 — English in v1): title **"Findly is sharing your location"**, body **"Your family can see where you are."**, with the app's monochrome status icon (§8) and a tap action opening the app's device-settings screen. The notification MUST NOT be silenced or disguised — Play treats that as a policy violation.

### 3.3 Android — 1440 (one day)

`PeriodicWorkRequest` with a 24-hour period is permitted, but the 000 §O3 semantics are what matter: **at least one fix per device-local calendar day, taken opportunistically**. The worker MUST check whether a fix already exists for the current local day and skip capture if so — never "24 h since the last fix".

### 3.4 iOS — all intervals

iOS cannot honor a fixed sub-15-minute cadence, and this spec does not pretend otherwise (000 §O2). The runtime is the union of three opportunistic triggers, all of which capture-and-queue through the same pipeline:

1. **`BGAppRefreshTask`** (identifier `be.dynex.findly.refresh`), rescheduled at the end of every run — the system decides actual frequency from usage patterns.
2. **Significant-location-change monitoring** (`startMonitoringSignificantLocationChanges`) — the battery-cheap always-on trigger; also relaunches the app after termination, which is why the queue must be durable (§2).
3. **Geofence transitions** (§6) and **foreground** app use.

A capture is taken when a trigger fires **and** at least `syncIntervalMinutes × 0.8` has elapsed since the last queued fix (the 0.8 factor keeps a slightly-early system wake useful instead of wasted). Devices on 5/10-minute targets will legitimately report `isStale: true` much of the time; the UI must present the interval as a target (004 §7).

### 3.5 Reacting to settings changes

`deviceSettings` arrives by three paths — the §5.1 `SETTINGS_CHANGED` push (best-effort accelerator), the 001 §5.1 flush piggyback (active devices), and the paused-device poll (§4). On **any** path, if `syncIntervalMinutes` changed the schedule MUST be rebuilt immediately (re-enqueue with `UPDATE` / reschedule the BG task, and start or stop the foreground service per §3.2); if `trackingEnabled` changed, apply §4.

## 4. Pause (`trackingEnabled: false`)

001 §5.1 is normative; on-device this means, in order: stop the periodic worker / cancel the BG task, stop the §3.2 foreground service if running, **unregister all platform geofences** (§6), and stop capturing. Transitions detected while paused are **dropped**, not queued.

Fixes captured **before** the pause stay in the queue and MAY be uploaded after resume — they are honest history. A paused device MUST NOT flush (`POST /locations` would return `403 TRACKING_PAUSED`).

**Resume is pull-based, never push-dependent:** while paused the client MUST re-check settings via `GET /devices` on every app foreground **and at least every 6 hours** (a low-frequency worker/BG task is the only thing that keeps running while paused). On observing `trackingEnabled: true`, restore the schedule (§3) and re-register geofences (§6.2).

## 5. Push handling (001 §8)

The client MUST ignore unknown `data.type` values (001 §1.1 forward compatibility) — including the reserved group types of 001 §8.7. All `data` values arrive as strings and MUST be parsed defensively; a malformed payload is dropped silently, never crashed on.

### 5.1 `LOCATE_REQUEST`

High-priority data-only. On receipt: if `now > expiresAt + 10 min`, **ignore it** (001 §6.3 — no GPS burn for a stale request). Otherwise capture one **high-accuracy** fix and `POST /locate-requests/{id}/fulfill` with `source: "locate"`. A paused device **still fulfills** (001 §6.3 — pause stops periodic surveillance, not an explicit request). Failure to obtain a fix within the §1.1 timeout: give up silently; the requester's poll surfaces the outcome. On iOS this arrives as a budgeted background push and is best-effort until the Location Push entitlement lands (000 §O1).

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

Android staging is already normative in 003 §11 (fine → background as a separate later request, rationale first, `POST_NOTIFICATIONS` independently). iOS mirrors it: **When-In-Use first**, then a deliberate **Always** upgrade prompt shown only after an in-app explanation of family/group background tracking, plus a separate notification-authorization request.

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

## 10. Non-goals & deferred

- **iOS Location Push Service Extension** — the reliable locate wake; gated on the Apple entitlement (000 §O1). v1 ships the best-effort background push of §5.1; the `locationPushToken` plumbing exists in 001 §4.1 but stays dormant.
- **Sub-15-minute cadence on iOS** — not achievable (000 §O2); explicitly not attempted.
- **Per-group sharing pause** — 000 §O13; pause stays device-global (005 §3).
- **Activity-recognition / motion-adaptive cadence** — a real battery win, but it needs its own spec and permission story; deferred until field data from M1 (docs/store-release-roadmap.md) justifies it.
- **Client-side geofence evaluation above 20 regions** — 000 §O9.

## 11. Error cases

No new 001 §10 codes. The runtime consumes the existing catalog: `TRACKING_PAUSED`, `DEVICE_NOT_FOUND`, `AUTH_TOKEN_EXPIRED`, `VALIDATION_FAILED` (dead-batch handling, 003 §10.3 / 004 §6), `LOCATION_BATCH_TOO_LARGE` (prevented client-side by the 100-fix split rule), `LIMIT_EXCEEDED`.

## 12. Test checklist (conforming clients — pure-logic tests; no platform framework in unit tests)

- **Capture policy:** accuracy tier per `source`; suppression when paused / permission-absent / <60 s duplicate; a stale queued fix is sent, not re-captured.
- **Queue durability:** survives simulated process death with the in-flight `PendingBatch` intact (same `batchId`, identical fixes on retry); insertion order preserved; 1 000-fix cap drops **oldest** first and logs a count only.
- **Scheduling:** interval → strategy selection (≥15 WorkManager / 5–10 foreground service / 1440 once-per-local-day with the same-day skip); rebuild on `syncIntervalMinutes` change from **all three** settings paths (push, piggyback, paused poll); foreground service starts and stops on exactly the specced conditions.
- **Pause:** worker stopped, service stopped, geofences unregistered, transitions dropped, no flush attempted; pre-pause fixes retained; resume via the 6-hour/foreground poll restores schedule **and** geofence registrations.
- **Push:** each `data.type` routed correctly; unknown and reserved types ignored; malformed payload dropped without crash; `LOCATE_REQUEST` past `expiresAt + 10 min` ignored, within the window fulfilled even while paused; `SETTINGS_CHANGED` applied as full state (both fields, idempotent, reorder-safe).
- **Geofencing:** full-replace re-registration on each §6.2 trigger; 20-region cap; all transitions reported regardless of notify flags; transition also queues a `source: "geofence"` fix; ETag mismatch in a response triggers re-sync.
- **Permissions:** staged request order; denial paths produce the banner state, not a crash; revocation mid-run stops capture; re-check on foreground.
- **Backoff:** exponential, capped at the sync interval; `DEVICE_NOT_FOUND` triggers re-registration then sign-out.
- **Logging invariant:** no test fixture or log statement emits coordinates, `deviceId`, tokens, or phone numbers.

## Open questions

None — deferred runtime matters are tracked in 000 §Open Items (O1 location push, O2 cadence limits, O9 geofence cap, O13 per-group pause) with v1 behavior fixed by this spec.
