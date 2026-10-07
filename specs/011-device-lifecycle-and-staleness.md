# 011 — Device lifecycle & staleness

## Goal

Two field problems with one root: a family roster that looks stale when nobody is actually stale. **(1) Ghost devices** — a reinstalled or replaced phone gets a fresh `deviceId` (001 §1.4, by design), so the old registration stays in the roster forever, shows *Stale*, and counts toward `maxDevices`; nothing can remove it (backlog H21, seen 2026-10-05). **(2) Force-quit iPhones** — the presence session (009 §1.3) holds a 15-minute cadence while the app is alive, but every 9–31 h gap in the field data starts when the user swipes Findly away and ends when they reopen it (backlog H19, 2026-10-03). This spec adds: a way to **remove** a device (§1), a server-computed **dormant** flag so long-silent devices stop cluttering the map (§2), a one-time **force-quit explainer** on iOS (§3), and a rate-limited server **stale nudge** push that reaches a force-quit app (§4). Decisions: 000 §D20 (2026-10-07). Wire shapes live in 001 (§4.2, §4.3, §4.4, §5.2, §8.8); storage in 002 (§2.4, §4.3) — this spec links to them and never redefines them.

## 1. Device removal (001 §4.4)

- **Who:** a **parent** may remove any device of any member of their family; **any user** may remove a device they own (member, parent or family-less). A non-parent removing another member's device → `403 AUTH_FORBIDDEN`. The device is resolved exactly like 001 §4.3's `PATCH` (the caller's own partition first, then — for a parent — the family-wide per-member scan); unresolvable → `404 DEVICE_NOT_FOUND`.
- **What is deleted** (002 §2.4 ordering): the `Devices` row, the device's `LastKnown` row, and its `IdempotencyMarkers` partition. **History is not purged** — `history/` day-blobs and geofence events written by the device stay and age out under normal retention (002 §4); they are honest records of locations that were really shared. `GroupLastKnown` is per *member*, not per device (002 §2.12), and is left alone: the only-newer rule means any later report from the member's other device overwrites it.
- **Effect on the device itself:** removal is **not a remote kill**. If the removed phone is in fact still running Findly, its next device-originated call gets `404 DEVICE_NOT_FOUND`, and 009 §9 makes it re-register — it reappears in the roster. Clients MUST say so in the confirmation copy (§1.1). This is the intended semantics: removal cleans up ghosts; pausing (`trackingEnabled: false`) is the control for a live phone.
- **Plan cap:** the removed device stops counting toward `maxDevices` immediately (the cap is a per-owner partition count, 001 §4.1).
- **Idempotency:** a second `DELETE` of the same `deviceId` → `404 DEVICE_NOT_FOUND` (the 001 §12.5 precedent: deletion is not silently repeatable by id).

### 1.1 Client — the Remove action (both platforms, normative)

On the 010 §4.2 Devices card:

- A **Remove device** action is shown when the caller is a parent **or** the card's `ownerUserId` is the caller — and **never on the card of the device the app is running on** (removing yourself would just re-register on the next call, per §1; to stop this phone, pause it or sign out). It sits **outside** 010 §4.2 bullet 3's parent-only gate, because owners may remove their own devices.
- Tapping it opens a confirmation dialog — title `Remove "<deviceName>"?`, body (normative, English per 000 §O8): `Its last known location is deleted. Location history stays until it expires. If this phone still has Findly, it will reappear the next time Findly opens on it.` — actions **Remove** (destructive style) / **Cancel**.
- On `204` the card disappears from the list and the map (the next 010 §3.6 refresh no longer returns it). Errors render on the card (010 §4.2 bullet 5): `AUTH_FORBIDDEN` → "Only a parent can remove another member's device."; `DEVICE_NOT_FOUND` → treat as success (it is already gone) and refresh the list.
- The card shows the device's last activity as a muted line, `Last seen <relative time>` from 001 §4.2's `lastSeenAt` (010 §3.1's relative-time formatter), so a ghost is recognisable before removing it; when `lastSeenAt` is absent the line is omitted. A device whose 001 §4.2 `isDormant` is `true` (§2) shows an **Inactive** status chip in place of Active — the card reads the flag from `GET /devices`, never from the map call and never by computing it on the client.

## 2. Dormant devices (001 §4.2 and §5.2 `isDormant`)

- **Definition (server-computed, defined once so both apps render identically — the `isStale` precedent):** a device is **dormant** when its most recent activity is more than **30 days** ago, where *most recent activity* is `lastSeenAt` if present, else `registeredAt` (002 §2.4). `DORMANT_AFTER_DAYS = 30` is a domain constant, not a plan limit (it is not a capability a plan sells).
- **Rendering on the family map (010 §3):** dormant devices are **excluded** from map markers, from the camera fit (010 §3.4), from the freshest-device choice (010 §3.5), and from the roster row's device chips. A member whose devices are **all** dormant renders the roster row's no-location state with the text `No recent location` (instead of `No location yet`), stays selectable, and keeps `Locate now` (010 §3.5 — locate is exactly what you want then). Members are never hidden — every member always appears (001 §5.2).
- **Devices screen:** dormant devices are **listed** (with the *Inactive* chip, §1.1) — this is the screen where they get removed.
- Dormancy is presentation only: a dormant device is still a valid locate target, still accepts reports, and becomes non-dormant the moment it calls in (its `lastSeenAt` refreshes, 001 §4.2).

## 3. Force-quit explainer (iOS only, client-only)

- **Signal:** the app records a local flag in `applicationWillTerminate(_:)` (UIKit app delegate; SwiftUI apps adopt it via `UIApplicationDelegateAdaptor`). iOS delivers this callback when the user swipes away an app that is still running in the background — which the presence session (009 §1.3) guarantees for intervals ≤ 30 — and not for a suspended app or an OS memory kill, so the flag is a deliberate-swipe signal, not a crash signal. The callback MUST only write the flag (it has a few seconds and no network).
- **Presentation:** on the next launch, after launch resolution has landed on the Family Map (010 §1.1), if the flag is set **and** this device's `trackingEnabled` is true **and** its `syncIntervalMinutes` ≤ 30, the app shows a one-time modal — title `Keep Findly open in the background`, body `Swiping Findly away stops sharing your location until you open it again. To keep sharing, leave Findly in the app switcher — it uses very little battery.`, single action **Got it**. Then it clears the flag and records `forceQuitExplainerShown`. It MUST NOT be shown again on this install for this user, regardless of later swipes (no nagging — the 009 §7 A25 principle). If the conditions are false the flag is cleared silently.
- Both the flag and `forceQuitExplainerShown` are part of the end-of-session local wipe (004's I43 routine) — a different user on the phone sees the explainer once too.
- Android has no equivalent: swiping an app away does not stop its foreground service (009 §3.2). The §4 nudge covers both platforms.

## 4. Stale nudge (server-initiated, both platforms)

A timer function sends a **visible** push to a device that should be reporting often but has gone quiet. An alert push is displayed by the OS even for a force-quit iOS app, so this is the one lever that works without the user remembering (the §3 explainer needs them to read it; this needs nothing).

### 4.1 Eligibility (normative — all must hold)

1. `trackingEnabled` is true **and** `syncIntervalMinutes` ≤ 30 (a presence device, 009 §1.3 — 60+ devices are *expected* to be quiet).
2. `staleNudgeEnabled` is true (001 §4.1; the owner's opt-out, §4.4).
3. The device has a push token and `pushInvalid` is false.
4. **Quiet:** `now − lastActivity > 120 min`, where `lastActivity` = `lastSeenAt`, else `registeredAt`. (The decision was `max(4 × interval, 2 h)`; for every interval condition 1 admits, 4 × interval ≤ 120, so it is a flat 2 h — written flat so nobody has to re-derive it.)
5. **Not given up:** `now − lastActivity ≤ 7 days`. A phone silent for a week is lost, broken or uninstalled; nudging it daily forever is spam, and §2's dormancy takes over the presentation.
6. **Rate limit:** `lastNudgedAt` is absent or `now − lastNudgedAt ≥ 24 h` — at most one nudge per device per 24 h.
7. **Quiet hours:** the send time, in **`Europe/Brussels`** local time, is in `[08:00, 21:00)`. The server holds no per-device time zone; every supported user is in BE/NL/FR/DE/LU (006 §6 SMS allowlist), all on Central European time, so one zone is correct for the whole user base. If the user base ever spans zones, this becomes a device-reported zone — out of scope here.

The rule is a pure function `isNudgeDue(device, now) → boolean` in `src/domain`, mutation-tested at every boundary (strict `>` on quiet, `≤` on the 7-day cap, `≥` on 24 h, the half-open hour window across DST changes).

### 4.2 The timer function (002 §4.3)

- `staleNudger`, timer-triggered **every 30 minutes** (`0 */30 * * * *`) — the 002 §4.1 group-sweeper precedent: domain logic pure in `src/domain`, the function file thin.
- Per run: enumerate `Devices` (a full-table scan — the table holds a few rows per family member; 48 small scans/day is negligible against 002 §5), evaluate §4.1 per row, and for each due device: **first** write `lastNudgedAt = now` (a timestamp-only merge that MUST NOT rewrite any other field — the 001 §11 `lastSeenAt` precedent), **then** send the §4.3 push. Claim-before-send means a crash between the two loses one nudge rather than risking a duplicate; a lost nudge is retried 24 h later by construction.
- Send outcomes follow 001 §8.5 token hygiene (`invalidToken` → `pushInvalid: true`). Any other failure is logged by count only and not retried before the next 24 h window.
- **Logging invariant:** counts (evaluated, due, sent, failed) only — never `deviceId`, user ids or tokens (`docs/security-review-checklist.md`).
- The function is **gated by an app setting** `STALE_NUDGE_ENABLED`: it sends only when the value is exactly `"true"`; absent or anything else means no send, so production can be switched off without a deploy. `local.settings.json.example` documents it with `"false"`.

### 4.3 The push (001 §8.8)

Visible on both platforms: an FCM `notification` block (the OS displays it even when the app is not running — required, since the target is precisely an app that is not running), Android channel `findly_sharing_status`, iOS `apns-push-type: alert` at priority 5. Title `Findly isn't sharing your location`, body `Open Findly to start sharing again.` — server-composed English (000 §O8). `data.type: "STALE_NUDGE"`, no other data. No personal data in the payload.

### 4.4 Client handling (both platforms)

- **Tap** opens the app; the ordinary foreground path does the work (009 §1.4 runs one full cycle and re-establishes presence). No special handler is needed.
- **Received while in the foreground:** suppress the banner — the app being open means it is not stale (the iOS `willPresent` returns no options; Android never sees a `notification`-block message in `onMessageReceived` while backgrounded, and while foregrounded drops it).
- **Android channel:** the app MUST create `findly_sharing_status` ("Sharing reminders", importance DEFAULT) at application start, so the system has the channel before the first nudge arrives (an FCM `notification` addressed to a missing channel falls back to a generic one the user cannot tell apart).
- **Opt-out (owner only):** on the 010 §4.2 card of **a device the caller owns** — any role, outside the parent gate — a toggle `Remind me when sharing stops` bound to `staleNudgeEnabled`, committing immediately via `PATCH /devices/{id}` (001 §4.3). It is not shown on other members' devices: the reminder is the device owner's own notification preference, and a parent cannot set it for someone else (001 §4.3 makes that `403`).

## 5. Error cases

No new 001 §10 codes:

- `DELETE /devices/{deviceId}`: `403 AUTH_FORBIDDEN` (non-parent, not the owner), `404 DEVICE_NOT_FOUND` (unknown, outside the caller's family, or already removed), `401` family per 001 §10.
- `PATCH` of `staleNudgeEnabled` by anyone but the owner → `403 AUTH_FORBIDDEN`; a non-boolean → `400 VALIDATION_FAILED`.
- The timer has no caller; its failures are logged by count only (§4.2).

## 6. Test checklist

**Backend (unit, pure domain + fakes; Azurite integration for the adapters):**

- Removal authorization matrix: parent → any family device `204`; owner (member) → own `204`; member → other member's device `403`; family-less owner → own `204`; device of another family / unknown → `404`; second delete → `404`.
- Removal coverage: `Devices` row, `LastKnown` row and the device's `IdempotencyMarkers` partition gone; history blobs and `GroupLastKnown` untouched; the `maxDevices` count drops by one; a subsequent `X-Device-Id` call from the removed device → `404 DEVICE_NOT_FOUND`; a never-created `LastKnown`/`IdempotencyMarkers` table is tolerated (002 §2 list-tolerance rule).
- `isDormant`: `lastSeenAt` at exactly 30 days → not dormant, just over → dormant; absent `lastSeenAt` falls back to `registeredAt`; present on every device object in 001 §5.2, including never-reported devices.
- `isNudgeDue`: each of the seven §4.1 conditions individually flips the outcome; quiet threshold is 120 min at every eligible interval (5 and 30 both; interval 60 → never eligible); 7-day cap boundary; 24 h rate-limit boundary; the `[08:00, 21:00)` window in `Europe/Brussels` on both sides of a DST transition.
- Timer: claim (`lastNudgedAt`) written before send and as a timestamp-only merge that cannot overwrite `syncIntervalMinutes`/`trackingEnabled`/`deviceName`/`pushToken`/`pushInvalid`/`staleNudgeEnabled`; `invalidToken` sets `pushInvalid`; `STALE_NUDGE_ENABLED` absent or not `"true"` → no send; logs carry counts only.
- `staleNudgeEnabled`: defaults `true` on first registration; preserved by re-registration (001 §4.1 — it is not reset by an upsert); owner may PATCH it, a parent on another member's device gets `403`; it appears in the §4.1 response object.
- Push shape for `STALE_NUDGE` matches 001 §8.8 byte-for-byte (snapshot).

**Clients (pure logic; no platform framework in unit tests):**

- Remove-action visibility: parent / owner / neither × this-device / other device (never on this-device).
- Remove result handling: `204` and `DEVICE_NOT_FOUND` both remove the card; `AUTH_FORBIDDEN` renders the card error.
- Roster partitioning over `isDormant`: dormant devices excluded from markers, camera fit and freshest-device choice; an all-dormant member renders `No recent location` and stays selectable.
- iOS explainer: shown iff flag ∧ tracking ∧ interval ≤ 30 ∧ not yet shown; shown at most once; flag cleared in every branch; both keys cleared by the end-of-session wipe.
- Nudge toggle: visible only on owned devices; commits one `PATCH` with `staleNudgeEnabled`.
- `STALE_NUDGE` in the foreground is suppressed; unknown types still ignored (009 §5).

## Open questions

None. Deferred: a per-device time zone for §4.1's quiet hours (only if the user base leaves CET); automatic retirement of dormant devices (H21 option (c)) — not chosen; a purge of a removed device's history — not chosen (2026-10-07, 000 §D20).
