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
- **Every table/container in this design is created lazily by its first write (§1 has no provisioning step).** Any list/enumerate call MUST therefore tolerate the table/container **not existing at all** and treat it identically to an empty result — never let `TableNotFound`/`ContainerNotFound` propagate as an error. This is a general rule, not specific to any one endpoint: it was first normative for the privacy-deletion paths (§4.2's write-time guard section) but is not limited to them — **any** list call reachable before that table's first writer has ever run is exposed the same way. `backend/src/adapters/tables/listTolerant.ts` / `backend/src/adapters/blobs/listTolerant.ts` are the shared, swallow-only-404 helpers; route new list call sites through them rather than re-deriving the pattern.
- **Merge cannot clear a field.** Azure Table Storage's Merge operation has no `null` type — passing a field as `null` in a Merge is silently dropped, not applied, so the call "succeeds" while leaving the old value in place. To actually clear a field, read the entity, then ETag-guarded `Replace` with every field that must survive explicitly included (Replace overwrites the *entire* entity — anything omitted is gone, not just the field you meant to clear). `TableUserRepo.clearFamilyMembership` is the reference implementation (read → preserve `displayName` → guarded Replace → bounded retry on conflict, throw on exhaustion since this is a correctness guarantee, not telemetry).

### 2.1 `Families`

| PK | RK | Properties |
|---|---|---|
| `{familyId}` | `meta` | `familyName`, `createdBy` (userId), `createdAt` |
| `{familyId}` | `member:{userId}` | `role` (`parent`\|`member`), `displayName`, `joinedAt` |
| `{familyId}` | `invite:{code}` | `expiresAt` (**index row** — canonical invite lives in §2.3) |

Access: point read (`meta`); partition range scan on `member:` = roster (001 §3.2). Roster mutations are guarded updates (last-parent rule checked inside the scan, 001 §3.5/3.6).

The `invite:` rows are the **invite reverse index** (same idiom as `Users`' `group:` rows, §2.2): written by invite creation (001 §3.3) *after* the canonical §2.3 row, read only by family deletion (§4.2) to find and revoke outstanding codes. The acceptance path never reads them. Consistency: a lost index row (partial-failure) merely leaves the canonical row to lazy 72 h expiry — harmless, because acceptance fails closed on a deleted family (001 §3.4); a lost canonical row makes the index row dead weight the family delete swallows.

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

Metrics: `locationBatches`, `fixes`, `locateRequests`, `geofenceEvents`, `apiCalls`, `exports` (001 §13.1 quota). Increment = read → +n → ETag-guarded merge, retry loop (max 3, then log-and-drop — usage is telemetry, not billing… yet). Contention is a single family's own devices: single-digit writes/minute worst case. The locate quota (001 §6.1) reads `{today}:locateRequests`.

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
- GDPR delete/export operate on the `{familyId}/…` prefixes (spec'd: [008](008-privacy-endpoints.md), wire shapes 001 §13, ordering §4.2 below) — the path design makes per-family erasure and per-user *history* erasure a prefix delete. The one non-prefix case: per-user erasure of the interleaved `events/` blobs is a filtered rewrite (§4.2).

### 4.1 Group sweeper (the project's first timer-triggered function)

Table Storage has no per-row TTL, and the group privacy promise (005 §2.4) requires **physical** deletion — so a **daily timer function** (domain logic pure in `src/domain/group/`, mutation-tested against fakes; the function file stays thin, per the hexagonal rule) performs it. Cadence: daily, off-peak UTC.

Per run: scan `GroupExpiry` (§2.13) partitions for dates `[today − 45 … today]` (46 tiny/empty scans — the window generously covers `groupGraceDays` plus any outage backlog; that bound is the documented catch-up horizon). For each row:

1. Point-read `Groups.meta`. Meta gone (owner deleted inline) → delete the orphaned expiry row, done.
2. `now < endsAt` (owner extended; this row is stale) → re-bucket to `date(endsAt)`, done — this re-check is what makes a partially-failed PATCH-time row move self-healing.
3. `policy = delete`, `now ≥ endsAt` → **hard delete**: the `GroupLastKnown` partition, the `GroupCodes` row, every member's `Users` `group:` row (roster read first), the `Groups` member rows + meta, and the expiry row **last** — a crash mid-way re-runs cleanly (every delete swallows 404).
4. `policy = grace`: `now < graceUntil` → delete the `GroupLastKnown` partition + `GroupCodes` row (locations and joinability die at `endsAt` even in grace; a reactivated group starts location-fresh and mints a new code), re-bucket the expiry row to `date(graceUntil)` with `action: "hardDelete"`. `now ≥ graceUntil` → full hard delete as (3).
5. `policy = archive` → delete the `GroupLastKnown` partition + `GroupCodes` row; keep meta, member rows, and reverse-index rows (the memento); delete the expiry row (never revisited — teardown happens via owner delete / member leave, 001 §12.5/12.8).

Owner `DELETE /groups/{id}` (001 §12.5) performs step 3 inline and synchronously. Together with the lazy read checks (005 §2.3), this delivers the normative guarantee: group location data is API-unreadable from `endsAt` and physically gone within ~24 h of the policy's deletion point.

### 4.2 Privacy deletion — coverage & ordering (001 §13, [008](008-privacy-endpoints.md))

Both operations run **synchronously in the request**, are **idempotent** (every delete swallows not-found — the §4.1 sweeper idiom), and are **re-callable until clean** after any crash.

**"Not-found" includes the table or container never having been created (normative).** Tables and blob containers in this design are created lazily by their first *write*, so an erasure can legitimately run against storage where a given table/container **does not exist at all** — and that is indistinguishable, for erasure purposes, from it existing and being empty. Both cases MUST be treated as "nothing to delete", not as an error. This applies to the **list/enumerate** step as much as the delete step: every one of these sequences is list-then-delete, and it is the *listing* of a never-created table (Azure `TableNotFound`) or container (`ContainerNotFound`) that fails first — the per-row delete's own not-found tolerance never gets a chance to help. Reachable in production, not just in a fresh environment: a family that never uses push-to-locate never creates `LocateRequests`, so a member's account deletion would hit exactly this. Note this is **not** symmetrical with the read paths, which already return "no data" naturally; it is the erasure paths' enumerate calls that need it explicitly. The ordering below is normative: it makes the auth boundary flip *first* (stopping concurrent writes structurally) and keeps the *retry pointer* alive until last.

**Account deletion (`DELETE /users/me`), in order:**

1. `Devices` partition — the subject's device-originated calls now fail `DEVICE_NOT_FOUND`; ingest stops.
2. `LastKnown` partition.
3. `IdempotencyMarkers` — one partition per deviceId collected in step 1 (on retry: none left, skip).
4. If in a family: `LocateRequests` rows in the family partition where `requestedBy` **or** `targetUserId` is the subject (`fixJson` holds coordinates — single-partition scan).
5. Owned groups: full §4.1-step-3 hard delete each (inline §12.5 semantics). Joined groups: leave semantics each — `Groups` member row, `GroupLastKnown` row, and the `Users` `group:` reverse-index row deleted together per group (retry finds only unprocessed groups).
6. `Usage` — the subject's **own uid-keyed** partition (§2.9). **Not conditional on family membership:** any period the account spent family-less accumulated rows under its own `uid` (001 §9's "per family/day — per user/day for family-less callers"), so a current family member can still hold them from before they joined, from between families, or from groups-only use. Family-**keyed** rows are household aggregates, explicitly *not* the subject's to erase (008 §2) — those go only with family deletion. Idempotent, so it is harmless when there are none.
7. If in a family and **not** cascading: `history/{familyId}/{uid}/` prefix delete, then the events filtered rewrite (below), then the `Families` member row.
8. If cascading (last parent / sole member — 008 §4.2): run the family deletion sequence below instead of step 7 (the whole-prefix wipe subsumes the rewrite).
9. `Users` profile row **last** — the completion marker and the retry pointer (its `familyId` and residual `group:` rows are how a re-call finds the remaining work).

**Family deletion (`DELETE /families/me`), in order:**

1. Every **other** member's `Users` profile: `familyId`/`role` → null — the auth boundary (001 §1.5) now routes **newly-arriving** reports family-less (no history appends) and their family reads to `FAMILY_NOT_FOUND`. This closes new requests only; requests already past their auth resolution are handled by the write-time guard below.
2. `Families` `member:` + `invite:` rows; each `invite:` row's canonical `Invites` row (§2.3) deleted with it.
3. `Entitlements`, `Usage` partition, `LocateRequests` partition.
4. Blob prefixes: `history/{familyId}/`, `events/{familyId}/`, `config/{familyId}/`.
5. `Families` `meta`.
6. The **caller's** profile flip (`familyId`/`role` → null) **last** — they must remain a parent-with-`familyId` so a retry can re-enter §1.6's role check and resume by `familyId` value (steps 2–5 proceed against a possibly-already-gone meta).

**Write-time family-existence guard (normative — closes the in-flight-request race).** Flipping profiles in step 1 stops *new* requests, but a request that already resolved its auth context (001 §1.5) still holds the old `familyId` and keeps executing. Because the history append is create-if-not-exists, such an in-flight `POST /locations` (001 §5.1) can land **after** the blob prefixes are wiped and silently recreate location coordinates under a family that was just erased — and since privacy deletion is deliberately one-shot with no sweeper (008 §1.2), that remnant would be permanent. It is reachable by any ordinary member with a batch in flight, and it contradicts the erasure guarantee of 008 §1.2/§2.

Therefore: **before the family-scoped history append and the family-keyed usage increment, the ingest path MUST re-verify that the family still exists**, rather than trusting the auth-context snapshot taken at request start. If it has been deleted mid-request, the caller is treated exactly as **family-less** for the remainder of that request (001 §5.1): last-known and group fan-out still apply, the history append is skipped, and usage is recorded under the caller's own `uid` partition. This reuses an existing point read (no new port) and costs one extra transaction per batch on the ingest path — negligible against §5's cost model, and the correct trade for an erasure guarantee.

The guard narrows but cannot mathematically eliminate the window (any check-then-write has one); combined with step 1's flip and the ordering above, the residual is a single in-flight batch, and no unbounded remnant can accumulate.

**The same guard applies to account deletion (normative).** Account deletion deletes the subject's `Devices` partition *first* precisely so their device-originated calls start failing `DEVICE_NOT_FOUND` — but that only stops requests which have yet to reach their `X-Device-Id` check (001 §1.2). A request already past it holds a validated `deviceId` and will still write `LastKnown`, an idempotency marker, and (when the family survives) a history line — **after** those very rows were erased. Therefore the ingest path MUST **also** re-verify, immediately before those writes, that the reporting device still exists; if it is gone, the batch is abandoned without writing (the account is being erased, so there is nothing legitimate left to record — unlike the family-deletion case there is no degraded-but-valid mode to fall back to). Two point reads per batch total (family meta + device row) is the accepted cost of the erasure guarantee, and both are skipped for callers to whom they cannot apply.

**Bounding and the retry contract (normative).** Erasure walks are unbounded in principle: `history/` spans up to the full retention per device, and the events rewrite must inspect every `events/{familyId}/` day-blob for the family's lifetime, since the subject's lines may be in any of them. Implementations MUST issue these blob deletes and rewrites with **bounded parallelism** (not one-at-a-time sequential round-trips) so a long-lived family does not approach the Functions request timeout. A timeout or 5xx mid-erasure is **safe but not complete**: every step is idempotent and the ordering leaves the profile row last, so the client's retry resumes and converges. Clients MUST therefore treat a 5xx/timeout on either deletion endpoint as "retry", never as "deleted" — and MUST NOT report success to the user until they observe the `204`. If real accounts ever outgrow a single synchronous request, the fix is a continuation/queue design, not a longer timeout; that is deliberately out of scope until measurement justifies it.

**Known, accepted edge (self-recoverable):** an invite accepted in the window between step 2's roster snapshot and step 5's meta deletion can leave that new member with a profile pointing at a deleted family plus an orphaned `member:` row. It cannot resurrect the family (001 §3.4 fails closed) and is reachable only via the deleting parent's own concurrent second session; the member self-recovers with `DELETE /users/me` (008 §4.1 is a no-op-safe idempotent path). Not worth a distributed lock.

**Events filtered rewrite (per-subject erasure from interleaved `events/` blobs):** for each `events/{familyId}/{y}/{M}/{d}.jsonl` blob: read all lines + capture the ETag; if no line carries the subject's `userId`, skip; else delete the blob with `If-Match` (a `412` — concurrent append — re-reads and retries, bounded like the §2.9 loop), recreate via create-if-not-exists (swallowing `409` — a §3.2 writer may have recreated it first), and re-append the filtered lines. No line of any *other* member is ever lost: the recreate-race unions the concurrent writer's fresh lines with the re-appended filtered history, and readers already sort (§3.2). Only the current UTC day-blob can race at all — past days are append-dead.

Cost bound: ≤ ~800 small blob reads + the table partition deletes — seconds at family scale (§5), well inside consumption-plan limits. The export read path (001 §13.1) walks the same inventory read-only and is bounded identically.

## 5. Cost model (order of magnitude)

Family of 5, 15-min intervals: ~480 fixes/day ≈ 480 appends + ~500 table transactions/day ≈ **well under €1/month** in transactions; storage ~15 MB/year of JSONL. The dominant cost is Functions consumption executions, still single-digit euros. Fits the 000 cost target with a wide margin.

## 6. Test checklist (storage adapters — integration tests, later session)

- Guarded-update races: invite single-use, last-known only-newer, usage increment retry.
- Append interleaving: two concurrent batch writers to the same day blob both land; reader sorts correctly.
- Batch spanning midnight UTC splits across two day blobs.
- Cursor round-trip across day boundaries and multi-device merge.
- Geofence ETag flow incl. `"0"` sentinel create and 412→409 mapping.
- Groups: join membership-insert race (double join → one winner + `GROUP_ALREADY_MEMBER`); code-rotate sequence survives a crash between steps (old or new code resolves, never neither); `GroupLastKnown` only-newer race (same idiom as §2.5); sweeper re-run after simulated crash mid-hard-delete converges (expiry row deleted last); expiry-row re-bucket self-heals after a partial `PATCH endsAt` move.
- Privacy deletion (§4.2): account-delete re-run after simulated crash at every step boundary converges (profile row last); family-delete likewise (caller's flip last); events filtered rewrite vs a genuinely concurrent §3.2 append — no other member's line lost, subject's lines gone; invite index + canonical row deleted together; export walks the full retention window (a blob older than `historyDays` appears in the export).
- Unit tests (domain) MUST NOT touch any of this — fakes implement the ports (`backend/src/ports/`).

## Open questions

None — purge timers and GDPR endpoints are tracked in 000 §Open Items (O7) / backlog notes above.
