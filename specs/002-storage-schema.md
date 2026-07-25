# 002 — Storage schema

## Goal

The complete, normative storage design: one Azure Storage account, Table Storage for point lookups, Blob Storage for history and config. No database server (000 §Architecture). Every access pattern is a point read or a single-partition scan — no cross-partition queries exist. Wire shapes referenced here are defined only in [001](001-api-contract.md).

## 1. Account & access

- One storage account (e.g. `stfindly`, see `docs/azure-setup.md`).
- The Function App's **system-assigned managed identity** holds `Storage Table Data Contributor` + `Storage Blob Data Contributor` on the account. No connection strings/keys in code or settings (except local Azurite).
- Local dev: Azurite; endpoints via `TABLES_ENDPOINT` / `BLOB_ENDPOINT` app settings (see `backend/local.settings.json.example`). Adapters MUST select credentials by endpoint host: `AzureNamedKeyCredential` with the well-known `devstoreaccount1` name/key when the host is `127.0.0.1`/`localhost`, `DefaultAzureCredential` otherwise.

## 2. Table Storage

General rules:

- All timestamps stored as ISO 8601 UTC strings (matching 001 §1.4), not Ticks.
- RowKey prefixes (`member:`, `device:`, …) keep entity kinds range-scannable within one partition.
- "Conditional insert" = `Add` (fails `409` if exists); "guarded update" = ETag-conditional `Update/Merge`.

### 2.1 `Families`

| PK | RK | Properties |
|---|---|---|
| `{familyId}` | `meta` | `familyName`, `createdBy` (userId), `createdAt` |
| `{familyId}` | `member:{userId}` | `role` (`parent`\|`member`), `displayName`, `joinedAt` |

Access: point read (`meta`); partition range scan on `member:` = roster (001 §3.2). Roster mutations are guarded updates (last-parent rule checked inside the scan, 001 §3.5/3.6).

### 2.2 `Users` — the auth hot path (+ group reverse index)

| PK | RK | Properties |
|---|---|---|
| `{userId}` | `profile` | `familyId` (**nullable** — family-less users, 001 §1.5), `role` (denormalized; **null iff `familyId` is null**), `displayName` |
| `{userId}` | `group:{groupId}` | `role` (`owner`\|`member`), `joinedAt` |

Every authenticated request does exactly one point read here (001 §1.5). `role` is denormalized from `Families`; both rows are written in the same logical operation on role change (no distributed transaction — `Families` is the source of truth, `Users` a cache; on mismatch the request re-reads `Families`).

The `group:` rows are the **"my groups" reverse index** (one partition scan next to the auth point read): `GET /groups` (001 §12.2) scans them and point-reads each `Groups.meta` (≤ `maxActiveGroups`, so ≤ 5 on free). Group `name`/`endsAt` are deliberately **not** denormalized here — rename/extend would need a fan-out update to every member's row with no self-healing on partial failure; a handful of meta point reads keeps `Groups.meta` the single source of truth. The location-ingest fan-out (001 §5.1) reads the same rows.

### 2.3 `Invites`

| PK | RK | Properties |
|---|---|---|
| `{inviteCode}` (canonical uppercase, no hyphen) | `invite` | `familyId`, `role`, `emailHint?`, `createdBy`, `createdAt`, `expiresAt`, `usedBy?`, `usedAt?` |

Accept flow (001 §3.4): point read → validate → **ETag-guarded merge** setting `usedBy`/`usedAt`. Exactly one concurrent accept wins; the loser sees a precondition failure → `INVITE_ALREADY_USED`.

### 2.4 `Devices` — keyed by owner

| PK | RK | Properties |
|---|---|---|
| `{ownerUserId}` | `device:{deviceId}` | `platform`, `model`, `appVersion`, `deviceName`, `pushToken`, `pushInvalid` (bool), `syncIntervalMinutes`, `trackingEnabled`, `registeredAt`, `lastSeenAt` |

Devices belong to **users**, not families (family-less users register devices too — 001 §1.5/§4.1): the partition is the owner, making the `X-Device-Id` ownership check (001 §1.2) a point read in the caller's own partition, and the `maxDevices` cap a per-user partition count (001 §4.1). Family-wide reads — the 001 §4.2 listing, the push fan-out list (001 §8.2/8.4), and the §4.1 registration-time `deviceIdInUse` conflict check (against every other member, not just the caller) — are the `Families` roster scan plus one small per-member partition scan each, issued in parallel (bounded by family size). `lastSeenAt` is updated at most once per minute per device (write-skipping to save transactions).

### 2.5 `LastKnown` — keyed by owner

| PK | RK | Properties |
|---|---|---|
| `{ownerUserId}` | `device:{deviceId}` | `lat`, `lon`, `accuracyM`, `altitudeM?`, `speedMps?`, `bearingDeg?`, `batteryPct`, `recordedAt`, `receivedAt`, `source` |

Same per-owner keying as `Devices` (family-less users have last-known too). Family live map (001 §5.2) = the `Families` `member:` roster scan + per-member `LastKnown` and `Devices` partition scans, joined in memory (≈ `2 × members + 1` small single-partition scans, `Promise.all`-parallel — bounded by family size, transaction cost negligible at family scale). Upsert rule: overwrite only if incoming `recordedAt` > stored `recordedAt` (guarded update with one retry on ETag race; second loss = skip, the other writer was newer).

### 2.6 `Entitlements`

| PK | RK | Properties |
|---|---|---|
| `{familyId}` | `entitlement` | `subscriptionStatus` (`free`\|`active`), `updatedAt` |

Created at family creation with `free` (001 §3.1). Read per request (cache per invocation). The `features` object is **always** computed from `PLAN_MATRIX[subscriptionStatus]` in domain code — never stored. **Family-less users have no row here**: their `features` is the implicit `"free"` (001 §9); a group owner's entitlement is resolved through their profile's `familyId` at join time (001 §12.6).

### 2.7 `LocateRequests`

| PK | RK | Properties |
|---|---|---|
| `{familyId}` | `req:{requestId}` | `targetUserId`, `targetDeviceId`, `requestedBy`, `status` (`pending`\|`fulfilled`\|`expired`\|`pushFailed`), `createdAt`, `expiresAt`, `fixJson?` |

Point read on poll (001 §6.2). Lazy expiry: a poll past `expiresAt` flips `pending → expired` in place. Coalescing (001 §6.1): partition scan filtered to `pending` + same `targetDeviceId` (tiny partitions — a family has at most a handful of rows here). Old rows are garbage — a cleanup timer function is a backlog item, not v1.

### 2.8 `IdempotencyMarkers`

| PK | RK | Properties |
|---|---|---|
| `{deviceId}` | `batch:{batchId}` | `receivedAt`, `fixCount` |
| `{deviceId}` | `event:{eventId}` | `receivedAt` |
| `{deviceId}` | `fix:{fixId}` | `receivedAt` (locate fulfills only, 001 §6.3) |

Conditional insert = the dedupe test (001 §5.1, §7.3; decision 000 §D7). Rows are tiny; purge timer = backlog item.

### 2.9 `Usage`

| PK | RK | Properties |
|---|---|---|
| `{familyId}` — or `{userId}` for family-less callers (001 §9) | `{yyyy-MM-dd}:{metric}` | `count` (Int32) |

Metrics: `locationBatches`, `fixes`, `locateRequests`, `geofenceEvents`, `apiCalls`. Increment = read → +n → ETag-guarded merge, retry loop (max 3, then log-and-drop — usage is telemetry, not billing… yet). Contention is a single family's own devices: single-digit writes/minute worst case. The locate quota (001 §6.1) reads `{today}:locateRequests`.

### 2.10 `Groups`

| PK | RK | Properties |
|---|---|---|
| `{groupId}` | `meta` | `name`, `ownerUserId`, `createdAt`, `endsAt`, `expiryPolicy` (`delete`\|`grace`\|`archive`), `code` (current join code, denormalized for display) |
| `{groupId}` | `member:{userId}` | `role` (`owner`\|`member`), `displayName` (per-group, 005 §1), `joinedAt` |

Mirrors `Families` (§2.1): point read (`meta`); partition scan on `member:` = roster + `memberCount`. Group **state is never stored** — it is derived from `now`/`endsAt`/`expiryPolicy` (005 §2.2), so there are no transition writes. Membership insert is a conditional insert (join race-safe); the `maxGroupMembers` capacity check is best-effort under concurrency (001 §12.6).

### 2.11 `GroupCodes`

| PK | RK | Properties |
|---|---|---|
| `{code}` (canonical uppercase, no hyphen) | `code` | `groupId`, `createdAt` |

Join (001 §12.6) = one point read. **Deliberately not the `Invites` table** (§2.3): invites are single-use with ETag-consume semantics and a fixed TTL; group codes are multi-use, live until group end or rotation, and are *deleted*, never consumed — overloading one entity with both behaviors would complicate the race-safe consume path for nothing. Rotate (001 §12.7) = conditional-insert new row (regenerate on collision, same idiom as invite creation) → guarded-update `Groups.meta.code` → delete old row; the sweeper's meta re-check makes a partial rotate self-healing. The row is deleted when the group passes `endsAt` (or is deleted), which is what makes a stale code fail as `GROUP_CODE_INVALID` (001 §12.6).

### 2.12 `GroupLastKnown`

| PK | RK | Properties |
|---|---|---|
| `{groupId}` | `member:{userId}` | `lat`, `lon`, `accuracyM`, `recordedAt`, `receivedAt`, `syncIntervalMinutes` (frozen at write — feeds `isStale`, 001 §12.10) |

One row per member per group — the member's single best position across their devices, **fan-out-on-write** (000 §D12): after the §2.5 upsert, location ingest (001 §5.1) scans the reporter's `Users` `group:` rows (§2.2), point-reads each `Groups.meta`, and upserts into each **active** group's partition with the same only-newer guarded update as §2.5. Group map read (001 §12.10) = one partition scan + the roster scan. **Deliberately field-minimal** (position-only, 005 §3): no `deviceId`, `batteryPct`, `source`, `altitudeM`, `speedMps`, `bearingDeg` — device identity and battery are family-internal detail. Privacy property: all group location data lives *only* in the `{groupId}` partition, so expiry deletion is a self-contained partition wipe, decoupled from family/user storage.

### 2.13 `GroupExpiry` — the sweeper's index

| PK | RK | Properties |
|---|---|---|
| `{yyyy-MM-dd}` (UTC date of the group's **next lifecycle action**) | `{groupId}` | `action` (`expire`\|`hardDelete`) |

Lets the sweeper (§4) find due groups with a handful of tiny date-partition scans — never a full table scan. Written at create (bucket = date of `endsAt`, `action: "expire"`); moved on `PATCH endsAt` (insert new bucket row, delete old — the sweeper re-verifies against `Groups.meta`, so a partial move is harmless); a `grace` group's row is re-bucketed to `date(graceUntil)` with `action: "hardDelete"` when its end date is processed.

## 3. Blob Storage

### 3.1 Containers & paths

| Container | Path | Blob type | Content |
|---|---|---|---|
| `history` | `{familyId}/{userId}/{deviceId}/{yyyy}/{MM}/{dd}.jsonl` | **Append blob** | One JSON line per location fix |
| `events` | `{familyId}/{yyyy}/{MM}/{dd}.jsonl` | **Append blob** | One JSON line per geofence event (all members interleaved; filter at read) |
| `config` | `{familyId}/geofences.json` | Block blob | The geofence document (001 §7.1); **the blob's ETag is the API ETag** |

Day boundaries are **UTC dates of `recordedAt`** (not `receivedAt` — a batch uploaded at 00:05 lands in the day the fixes happened; one batch may append to two day-blobs).

### 3.2 Append semantics (000 §D6)

- Writer: `AppendBlock` per day-group of a batch; create-if-not-exists first (`If-None-Match: *`, swallow `409`).
- `AppendBlock` is atomic per call → concurrent Function instances interleave safely with **no lease, no ETag loop**. Lines may be out of order across blocks; readers sort by `recordedAt`.
- Capacity: 50 000 blocks/blob vs ≤ 288 appends/device-day at the tightest interval — 170× headroom even if every fix were its own block.
- History line (fix): `{"fixId":"…","recordedAt":"…","receivedAt":"…","lat":…,"lon":…,"accuracyM":…,"altitudeM":…,"speedMps":…,"bearingDeg":…,"batteryPct":…,"source":"periodic"}` — optional fields omitted, not null.
- Event line: `{"eventId":"…","userId":"…","deviceId":"…","geofenceId":"…","geofenceName":"Home"|null,"lat":51.0543|null,"lon":3.7174|null,"radiusM":150|null,"transition":"enter","recordedAt":"…","receivedAt":"…"}` — `geofenceName`, `lat`, `lon`, `radiusM` are frozen at write time so moving/renaming/deleting a geofence never rewrites history and events stay plottable (001 §7.4); all four are `null` when the `geofenceId` was unknown at write time.

### 3.3 History read & cursor (001 §5.3, §7.4)

- Reader walks day blobs ascending from `from` to `to`, streaming lines, filtering (`deviceId`, `userId`), sorting per day by `recordedAt`, until `limit` is filled.
- Cursor: base64url JSON — `{"d":"2026-07-05","o":{"<deviceId>":12800}}` — resume date + per-device-blob byte offset (events: single `"o":12800`). Opaque to clients; format may change without notice.
- Duplicate `fixId`s within a day (crash-retry edge) are dropped at read time (last write wins by `receivedAt`).

### 3.4 Geofence config concurrency (001 §7.2)

`PUT` = upload with `If-Match: <etag>` (or `If-None-Match: *` for the `"0"` sentinel first write). Storage's `412` maps to `409 GEOFENCE_VERSION_CONFLICT`. `version` lives inside the JSON and increments on every successful PUT; the ETag is the concurrency token, `version` is the human-readable one.

## 4. Retention & lifecycle

Lifecycle management policy on the account (applied by `docs/azure-setup.md`; JSON below is normative):

```json
{ "rules": [ {
    "name": "history-retention",
    "enabled": true,
    "type": "Lifecycle",
    "definition": {
      "filters": { "blobTypes": ["appendBlob"], "prefixMatch": ["history/", "events/"] },
      "actions": { "baseBlob": {
        "delete": { "daysAfterModificationGreaterThan": 400 } } } } } ] }
```

- Physical retention: delete at 400 d. Azure lifecycle management supports **only the delete action for append blobs** (no `tierToCool`) — history blobs stay in the hot tier until deletion, which at ~15 MB/year is cost-irrelevant.
- The **free-tier read window** (`features.limits.historyDays: 90`) is enforced in the API (001 §5.3), *not* by lifecycle — upgrading a family to a longer window later requires zero data migration (data exists to 400 d regardless).
- Tables (`LastKnown`, markers, usage) are small; no lifecycle needed. Marker/locate-request purge timers = backlog.
- GDPR delete/export (000 §O7) will operate on the `{familyId}/…` prefixes — the path design makes per-family and per-user erasure a prefix delete.

### 4.1 Group sweeper (the project's first timer-triggered function)

Table Storage has no per-row TTL, and the group privacy promise (005 §2.4) requires **physical** deletion — so a **daily timer function** (domain logic pure in `src/domain/group/`, mutation-tested against fakes; the function file stays thin, per the hexagonal rule) performs it. Cadence: daily, off-peak UTC.

Per run: scan `GroupExpiry` (§2.13) partitions for dates `[today − 45 … today]` (46 tiny/empty scans — the window generously covers `groupGraceDays` plus any outage backlog; that bound is the documented catch-up horizon). For each row:

1. Point-read `Groups.meta`. Meta gone (owner deleted inline) → delete the orphaned expiry row, done.
2. `now < endsAt` (owner extended; this row is stale) → re-bucket to `date(endsAt)`, done — this re-check is what makes a partially-failed PATCH-time row move self-healing.
3. `policy = delete`, `now ≥ endsAt` → **hard delete**: the `GroupLastKnown` partition, the `GroupCodes` row, every member's `Users` `group:` row (roster read first), the `Groups` member rows + meta, and the expiry row **last** — a crash mid-way re-runs cleanly (every delete swallows 404).
4. `policy = grace`: `now < graceUntil` → delete the `GroupLastKnown` partition + `GroupCodes` row (locations and joinability die at `endsAt` even in grace; a reactivated group starts location-fresh and mints a new code), re-bucket the expiry row to `date(graceUntil)` with `action: "hardDelete"`. `now ≥ graceUntil` → full hard delete as (3).
5. `policy = archive` → delete the `GroupLastKnown` partition + `GroupCodes` row; keep meta, member rows, and reverse-index rows (the memento); delete the expiry row (never revisited — teardown happens via owner delete / member leave, 001 §12.5/12.8).

Owner `DELETE /groups/{id}` (001 §12.5) performs step 3 inline and synchronously. Together with the lazy read checks (005 §2.3), this delivers the normative guarantee: group location data is API-unreadable from `endsAt` and physically gone within ~24 h of the policy's deletion point.

## 5. Cost model (order of magnitude)

Family of 5, 15-min intervals: ~480 fixes/day ≈ 480 appends + ~500 table transactions/day ≈ **well under €1/month** in transactions; storage ~15 MB/year of JSONL. The dominant cost is Functions consumption executions, still single-digit euros. Fits the 000 cost target with a wide margin.

## 6. Test checklist (storage adapters — integration tests, later session)

- Guarded-update races: invite single-use, last-known only-newer, usage increment retry.
- Append interleaving: two concurrent batch writers to the same day blob both land; reader sorts correctly.
- Batch spanning midnight UTC splits across two day blobs.
- Cursor round-trip across day boundaries and multi-device merge.
- Geofence ETag flow incl. `"0"` sentinel create and 412→409 mapping.
- Groups: join membership-insert race (double join → one winner + `GROUP_ALREADY_MEMBER`); code-rotate sequence survives a crash between steps (old or new code resolves, never neither); `GroupLastKnown` only-newer race (same idiom as §2.5); sweeper re-run after simulated crash mid-hard-delete converges (expiry row deleted last); expiry-row re-bucket self-heals after a partial `PATCH endsAt` move.
- Unit tests (domain) MUST NOT touch any of this — fakes implement the ports (`backend/src/ports/`).

## Open questions

None — purge timers and GDPR endpoints are tracked in 000 §Open Items (O7) / backlog notes above.
