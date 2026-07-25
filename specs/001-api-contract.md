# 001 — Backend API contract

## Goal

The complete, normative wire contract for the Findly backend. Backend, Android, and iOS sessions build against this document independently; **any shape not defined here does not exist**. Storage layouts live in [002](002-storage-schema.md); product context in [000](000-overview.md).

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively.

---

## 1. Conventions

### 1.1 Base URL & versioning

- All routes are prefixed **`/api/v1`**. Breaking changes bump the path version; additive changes (new optional fields, new endpoints) do not.
- Clients MUST ignore unknown response fields (forward compatibility).

### 1.2 Headers

| Header | Direction | Rule |
|---|---|---|
| `Authorization: Bearer <Firebase ID token>` | request | REQUIRED on every endpoint (no anonymous endpoints exist) |
| `X-Device-Id: <uuid>` | request | REQUIRED on device-originated calls: `POST /locations`, `POST /geofence-events`, `POST /locate-requests/{id}/fulfill`. MUST match a device registered to the calling user, else `404 DEVICE_NOT_FOUND`. |
| `Content-Type: application/json; charset=utf-8` | both | All bodies are JSON |
| `If-None-Match` / `If-Match` / `ETag` | both | Geofence config sync only (§7.1–7.2) |

### 1.3 Envelopes

Every **success** response:

```json
{ "data": { /* endpoint payload */ }, "features": { /* §9 */ } }
```

Every **error** response:

```json
{ "error": { "code": "FAMILY_NOT_FOUND", "message": "debug text, never shown raw to users",
             "details": { /* optional, code-specific */ }, "requestId": "r_a1b2c3d4" } }
```

- `code` is machine-stable and comes only from the catalog in §10.
- `requestId` is server-generated per request and echoed in server logs (correlation).
- Error responses MAY include `features` but clients MUST NOT rely on it.
- **Enveloping exceptions (exhaustive):** the body-less successes (`204` — §3.6, §12.5, §12.8, §12.9, §13.2, §13.3; `304` — §7.1) and the **export download** (§13.1), whose success body is the export document itself, unenveloped.

### 1.4 Data conventions

| Thing | Rule |
|---|---|
| Timestamps | ISO 8601 UTC with `Z`, e.g. `2026-07-19T09:05:12Z` (milliseconds optional) |
| `familyId` | `fam_` + 20 chars `[A-Za-z0-9]` (server-generated) |
| `groupId` | `grp_` + 20 chars `[A-Za-z0-9]` (server-generated) |
| `requestId` (locate) | `lr_` + 20 chars `[A-Za-z0-9]` (server-generated) |
| `userId` | The Firebase Auth `uid`, opaque string |
| `deviceId` | Client-generated UUIDv4, stable per app install **and per signed-in user** — clients MUST generate a fresh `deviceId` when the signed-in user changes. `POST /devices` with a `deviceId` already registered to a different user → `400 VALIDATION_FAILED`, `details.reason: "deviceIdInUse"`, enforced **family-wide** when the registering user has a family (any other member's `deviceId`, not just the caller's own — §4.1); a family-less caller is checked only against their own prior registrations (their `deviceId`s are never exposed to any other user, unlike §4.2's open-family visibility, so no equivalent collision risk exists there). |
| `batchId`, `fixId`, `eventId` | Client-generated UUIDv4 |
| `geofenceId` | Client-chosen slug `gf_[a-z0-9-]{1,30}`, unique within the family config |
| Invite code / group join code | Server-generated, 8 chars of Crockford base32 (no I/L/O/U). Canonical form: uppercase, no hyphen. Clients MAY display/accept `XXXX-XXXX`; the server accepts case-insensitively and ignores hyphens. Family invite codes are **single-use** (§3.3); group join codes are **multi-use** until the group ends or the code is rotated (§12.6–12.7). |
| Coordinates | `lat` ∈ [−90, 90], `lon` ∈ [−180, 180], WGS 84 decimal degrees |
| `accuracyM` | Horizontal accuracy radius in meters (68 % confidence), 0–10 000 |
| `speedMps`, `bearingDeg`, `altitudeM` | m/s ≥ 0; degrees [0, 360); meters (optional fields) |
| `batteryPct` | Integer 0–100 |
| `syncIntervalMinutes` | Allowed set exactly: `5, 10, 15, 30, 60, 120, 1440` — anything else → `VALIDATION_FAILED`. Additionally MUST be ≥ `features.limits.minSyncIntervalMinutes` → else `402 LIMIT_EXCEEDED`, `details.limit: "minSyncIntervalMinutes"` (§9). On iOS, sub-15-minute values are targets, not guarantees (000 §O2). |

### 1.5 Auth context resolution (every request)

A **profile** (the caller's `Users` row, 002 §2.2) and a **family** are distinct: a profile always has a `displayName`, and MAY have `familyId: null` / `role: null` — a family-less user (groups only, §12). Resolution:

1. Verify the Firebase ID token (§2). Failure → 401 (§10).
2. Load the caller's profile (`Users` table, 002 §2.2): `uid → { familyId | null, role | null, displayName }`.
3. If **no profile exists**, the only permitted endpoints are the four profile-bootstrapping ones — `POST /families` (§3.1), `POST /invites/accept` (§3.4), `POST /groups` (§12.1), `POST /groups/join` (§12.6) — each of which creates the profile, taking `displayName` from the request — plus `DELETE /users/me` (§13.2), which is permitted without a profile as an idempotent no-op (008 §4.1: covers the never-bootstrapped state and makes deletion crash-retry converge). Everything else → `404 PROFILE_NOT_FOUND`.
4. If the profile has **no family** (`familyId: null`), the family-scoped endpoints (§3.2–3.6, §5.2, §5.3, §6, §7) → `404 FAMILY_NOT_FOUND`. Device endpoints (§4), location reporting (§5.1), and group endpoints (§12) work without a family.
5. Role checks per endpoint table (§1.6). Role/pause state is read from storage on **every** request — this, not token revocation, is the enforcement boundary (§2.4).

### 1.6 Endpoint index & required role

| § | Method & path | Caller |
|---|---|---|
| 3.1 | `POST /api/v1/families` | authenticated user **without** a family |
| 3.2 | `GET /api/v1/families/me` | member |
| 3.3 | `POST /api/v1/families/me/invites` | parent |
| 3.4 | `POST /api/v1/invites/accept` | authenticated user **without** a family |
| 3.5 | `PATCH /api/v1/families/me/members/{userId}` | parent |
| 3.6 | `DELETE /api/v1/families/me/members/{userId}` | parent |
| 4.1 | `POST /api/v1/devices` | member (registers/updates own device) |
| 4.2 | `GET /api/v1/devices` | member |
| 4.3 | `PATCH /api/v1/devices/{deviceId}` | parent; owner for `pushToken` only |
| 5.1 | `POST /api/v1/locations` | member, own device (`X-Device-Id`) |
| 5.2 | `GET /api/v1/locations/latest` | member |
| 5.3 | `GET /api/v1/locations/history` | member |
| 6.1 | `POST /api/v1/locate-requests` | member |
| 6.2 | `GET /api/v1/locate-requests/{requestId}` | requesting member |
| 6.3 | `POST /api/v1/locate-requests/{requestId}/fulfill` | target device (`X-Device-Id`) |
| 7.1 | `GET /api/v1/geofences` | member |
| 7.2 | `PUT /api/v1/geofences` | parent |
| 7.3 | `POST /api/v1/geofence-events` | member, own device (`X-Device-Id`) |
| 7.4 | `GET /api/v1/geofence-events` | member |
| 12.1 | `POST /api/v1/groups` | any authenticated user (profile created if absent) |
| 12.2 | `GET /api/v1/groups` | user with a profile |
| 12.3 | `GET /api/v1/groups/{groupId}` | group member |
| 12.4 | `PATCH /api/v1/groups/{groupId}` | group owner |
| 12.5 | `DELETE /api/v1/groups/{groupId}` | group owner |
| 12.6 | `POST /api/v1/groups/join` | any authenticated user (profile created if absent) |
| 12.7 | `POST /api/v1/groups/{groupId}/code/rotate` | group owner |
| 12.8 | `POST /api/v1/groups/{groupId}/leave` | group member (not owner) |
| 12.9 | `DELETE /api/v1/groups/{groupId}/members/{userId}` | group owner |
| 12.10 | `GET /api/v1/groups/{groupId}/locations/latest` | group member |
| 13.1 | `GET /api/v1/export` | any user with a profile (self); parent for another family member |
| 13.2 | `DELETE /api/v1/users/me` | any authenticated user (works without a profile — §1.5.3) |
| 13.3 | `DELETE /api/v1/families/me` | parent |

In the "Caller" column, **member/parent** mean family roles (§3); **group member/owner** mean roles within the addressed group (§12). Family-role violation → `403 AUTH_FORBIDDEN`; non-membership of the addressed group → `404 GROUP_NOT_FOUND` (existence masked, §12); group-role violation by a member → `403 AUTH_FORBIDDEN`.

---

## 2. Authentication

### 2.1 Client side

Mobile apps authenticate users with **Firebase Phone Authentication** (SMS one-time code — the phone number *is* the account; no email/password, Google, or other providers exist; sign-in flow and Firebase-project requirements in [`006-phone-auth.md`](006-phone-auth.md), setup steps in `docs/azure-setup.md`) and send the current Firebase **ID token** as `Authorization: Bearer <token>` on every call. Clients MUST refresh tokens via the Firebase SDK (tokens live ~1 h) and retry once on `AUTH_TOKEN_EXPIRED`.

The sign-in provider is invisible to this contract: server verification (§2.2) uses only `iss`/`aud`/signature/`exp`/`iat`/`sub`. The token's `phone_number` claim is **not read, returned, or stored** server-side in v1 — `userId` stays the opaque `uid` (006 §2).

### 2.2 Server-side verification (credential-free)

The backend verifies tokens statelessly with `jose`:

- JWKS: `createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"))` — jose caches per `Cache-Control`.
- Required claims: alg `RS256`; `iss === "https://securetoken.google.com/" + FIREBASE_PROJECT_ID`; `aud === FIREBASE_PROJECT_ID`; `exp` in the future; `iat` in the past; `sub` (= `uid`) non-empty.
- `FIREBASE_PROJECT_ID` is an app setting. **No Google credential is used for auth.**
- These claims are identical across Firebase sign-in providers; the sign-in method is invisible to this verification.

### 2.3 Local development

`AUTH_MODE=insecure-local` accepts **unsigned** tokens (Firebase Auth emulator / hand-crafted JWTs; `sub` is trusted as-is). The backend MUST refuse to start in this mode when running in Azure (detected via `WEBSITE_INSTANCE_ID`).

### 2.4 Known limitation (accepted)

Without the Firebase Admin SDK there is **no revocation check**. Accepted because: tokens live 1 h, and the actual enforcement boundary is our own storage — role, membership, and `trackingEnabled` are re-read on every request (§1.5). Removing a member or pausing a device takes effect on their next API call regardless of token validity.

---

## 3. Family management

### 3.1 Create family — `POST /families`

Caller MUST NOT already belong to a family (→ `409 FAMILY_ALREADY_MEMBER`). Creator becomes a `parent`.

```json
// request
{ "familyName": "Wauters", "displayName": "Eric" }
// validation: familyName 1–50 chars; displayName 1–30 chars

// 201 → data
{ "familyId": "fam_9J2Kq7Lm3NpR5sTvWxYz",
  "familyName": "Wauters",
  "member": { "userId": "<uid>", "role": "parent", "displayName": "Eric" } }
```

Side effects: `Users` profile row written; `Entitlements` record created with `subscriptionStatus: "free"`; usage `apiCalls` recorded (§9).

### 3.2 Get my family — `GET /families/me`

```json
// 200 → data
{ "familyId": "fam_…", "familyName": "Wauters", "createdAt": "2026-07-19T08:00:00Z",
  "me": { "userId": "<uid>", "role": "parent" },
  "members": [
    { "userId": "u1", "role": "parent", "displayName": "Eric",  "joinedAt": "…" },
    { "userId": "u2", "role": "member", "displayName": "Noor",  "joinedAt": "…" } ] }
```

### 3.3 Create invite — `POST /families/me/invites` (parent)

```json
// request  — role of the invitee; emailHint is recorded, never used to send mail (000 §O5)
{ "role": "member", "emailHint": "kid@example.com" }
// role ∈ {parent, member}; emailHint optional, valid email if present

// 201 → data
{ "inviteCode": "7F3K9QRZ", "role": "member", "expiresAt": "2026-07-22T10:00:00Z" }
```

Invites are **single-use** and expire after **72 h**. The parent shares the code out-of-band (OS share sheet).

Side effect: a family-side **index row** is recorded (002 §2.1) so family deletion (§13.3) can find and revoke outstanding invites; the acceptance path never reads it.

### 3.4 Accept invite — `POST /invites/accept`

Caller MUST NOT already belong to a family (→ `409 FAMILY_ALREADY_MEMBER`).

```json
// request
{ "inviteCode": "7f3k-9qrz", "displayName": "Noor" }

// 200 → data
{ "familyId": "fam_…", "familyName": "Wauters", "role": "member" }
```

Errors: unknown/consumed code → `400 INVITE_INVALID` / `400 INVITE_ALREADY_USED`; past `expiresAt` → `410 INVITE_EXPIRED`. Consumption is race-safe (ETag-conditional, 002 §2) — exactly one concurrent accept wins. **Fail-closed on deleted families (008 §5.3):** acceptance MUST verify the family still exists before creating any membership — a code whose family is gone (family deleted, §13.3) → `400 INVITE_INVALID`, indistinguishable from an unknown code; a deleted family can never be resurrected through a straggler invite row.

### 3.5 Update member — `PATCH /families/me/members/{userId}` (parent)

```json
// request — at least one field
{ "role": "parent", "displayName": "Noor W." }

// 200 → data: the updated member object (§3.2 shape)
```

A parent MUST NOT demote themselves if they are the last parent (→ `400 VALIDATION_FAILED`, `details.reason: "lastParent"`).

### 3.6 Remove member — `DELETE /families/me/members/{userId}` (parent)

`204` (empty body — one of the body-less success responses, together with §7.1's `304` and the `204`s of §12.5/§12.8/§12.9/§13.2/§13.3). Removes membership, profile link, and the member's device registrations. History blobs are untouched (retention policy governs them). The last parent cannot remove themselves (`400 VALIDATION_FAILED`, `details.reason: "lastParent"`).

---

## 4. Devices

### 4.1 Register / update own device — `POST /devices`

Upsert keyed on `deviceId`. First registration applies defaults (`syncIntervalMinutes: 15`, `trackingEnabled: true`, `deviceName` = `model` when omitted); later calls from the owner update `pushToken`, `locationPushToken`, `appVersion`, `model`, `platform` but MUST NOT reset parent-managed settings (`syncIntervalMinutes`, `trackingEnabled`, `deviceName`). **Omitted token fields are left unchanged:** an update that carries no `pushToken`/`locationPushToken` never clears a previously stored one — a token is replaced only by a later call that supplies a new value (a device stays a valid push-to-locate target across a token-less `appVersion`-only re-registration). Any successful registration that *does* supply a fresh token clears `pushInvalid` (§8.5).

Clients MUST call this on: first launch after sign-in, every FCM token refresh, and every app update.

```json
// request — deviceId, platform, model, appVersion REQUIRED; all other fields OPTIONAL
{ "deviceId": "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b",
  "platform": "android",                 // "android" | "ios"
  "model": "Pixel 8",                    // 1–60 chars
  "appVersion": "1.0.0",
  "pushToken": "fcm-token…",             // OPTIONAL — may be absent until FCM/APNs registration completes
                                         //   (async on both platforms); without a valid token the device
                                         //   cannot be a preferred locate target (§6.1); MUST be re-POSTed
                                         //   the moment it becomes available and on every refresh (000 §O4)
  "locationPushToken": "apns-loc…",      // OPTIONAL, iOS only — APNs Location Push token (§8.1, 000 §O1)
  "deviceName": "Noor's phone" }         // OPTIONAL, 1–40 chars; only applied on FIRST registration

// 201 (created) / 200 (updated) → data
{ "deviceId": "…", "ownerUserId": "<uid>", "platform": "android",
  "deviceName": "Noor's phone", "model": "Pixel 8", "appVersion": "1.0.0",
  "syncIntervalMinutes": 15, "trackingEnabled": true, "pushInvalid": false }
```

New registrations count against `features.limits.maxDevices` — a **per-user** cap: the count is the registering user's own devices (→ `402 LIMIT_EXCEEDED`, `details.limit: "maxDevices"`); upserts of an existing `deviceId` never do. Push tokens (`pushToken`, `locationPushToken`) are write-only: they never appear in any response. Devices are stored per-owner (002 §2.4) — registration does not require a family.

The `deviceIdInUse` conflict check (§1.4) is **family-wide** when the registering caller has a family: a new registration is rejected if the `deviceId` is already registered to *any other member of the same family*, not just the caller's own prior registrations (a fan-out check across the family's per-owner partitions, 002 §2.4 — same cost model as §4.2's listing and §8.2/§8.4's push fan-out). This closes a visibility-driven risk: §4.2's open-family device listing lets every member read every other member's `deviceId`, so without this check a member could deliberately re-register a sibling's known `deviceId` under their own account and silently hijack any later by-`deviceId` lookup (a parent's `PATCH /devices/{deviceId}`, §4.3; a locate request's `targetDeviceId`, §6.1) into resolving to the attacker's device instead. A family-less caller's `deviceIdInUse` check stays scoped to their own prior registrations only — family-less `deviceId`s are never exposed to any other user (§4.2 restricts a family-less caller's listing to their own devices), so no equivalent visibility channel — and therefore no equivalent collision risk — exists there.

### 4.2 List family devices — `GET /devices`

Open family: all members see all devices and their settings (only parents can change them). A **family-less caller** gets their **own devices only** (same response shape; `ownerDisplayName` = their profile `displayName`).

```json
// 200 → data
{ "devices": [ { /* §4.1 response object */, "ownerDisplayName": "Noor", "lastSeenAt": "2026-07-19T09:05:14Z" } ] }
```

`lastSeenAt` = server receive time of the device's most recent authenticated call.

### 4.3 Update device settings — `PATCH /devices/{deviceId}`

```json
// request — at least one field
{ "syncIntervalMinutes": 30, "trackingEnabled": false,
  "deviceName": "Noor's tablet", "pushToken": "new-token…" }
```

- **Parent:** may set any field. Setting `trackingEnabled: false` is the "pause" button.
- **Owner (non-parent, in a family):** may set **only** `pushToken`; any other field → `403 AUTH_FORBIDDEN`.
- **Family-less owner:** may set **any field** of their own device — with no family there is no parent, so the user is their own admin. (Pause stays device-global: a paused device reports to no family and no group — 005 §3.)
- On any change to `syncIntervalMinutes` / `trackingEnabled`, the backend sends a `SETTINGS_CHANGED` push (§8.3) to that device so it can apply immediately. The push is a best-effort accelerator — the guaranteed pickup paths are defined in §5.1 (piggyback for active devices, settings poll for paused ones).

`200` → data: updated device object (§4.1 shape).

---

## 5. Location reporting & reading

### 5.1 Report locations (batch) — `POST /locations`

The battery-critical path. Devices SHOULD batch fixes accumulated while offline and upload in one call. `fixes` MUST contain **1–100** entries: more → `400 LOCATION_BATCH_TOO_LARGE`; empty → `400 VALIDATION_FAILED` (settings sync uses `GET /devices` / `GET /geofences`, never empty batches).

```json
// request
{ "batchId": "b7f2c1d0-…-uuid",
  "fixes": [
    { "fixId": "a1e2…-uuid",
      "recordedAt": "2026-07-19T09:05:12Z",     // device clock, see skew rule below
      "lat": 51.0543, "lon": 3.7174,
      "accuracyM": 12.5,
      "altitudeM": 8.0,                          // optional
      "speedMps": 0.0,                           // optional
      "bearingDeg": 0,                           // optional
      "batteryPct": 78,
      "source": "periodic" } ] }                 // "periodic" | "locate" | "geofence" | "manual"

// 200 → data
{ "accepted": 12, "duplicates": 0, "lastKnownUpdated": true,
  "deviceSettings": { "syncIntervalMinutes": 15, "trackingEnabled": true },
  "geofenceEtag": "\"0x8DC5F3A9B2C1D40\"" }
```

Rules:

- **Idempotency (batch-level):** the server conditionally inserts a marker for `(deviceId, batchId)` — **only when the batch is accepted**. A replayed accepted batch returns `200 { "accepted": 0, "duplicates": <n>, … }`. A `batchId` permanently identifies a frozen set of fixes: retries after transport failures or 5xx MUST resend identical content under the same `batchId`; fixes recorded later go into a **new** batch; a queue larger than 100 fixes MUST be split into multiple batches.
- **Definitive rejection (any 4xx):** no marker was written — the batch is dead. The client SHOULD drop or correct the offending fixes (`details.fields`) and resubmit the remainder under a **new** `batchId`.
- **Clock skew:** any fix with `recordedAt` more than 5 minutes in the future (server clock) fails the whole batch with `400 VALIDATION_FAILED`, `details.fields: ["fixes[3].recordedAt"]`. Server stamps `receivedAt` on every stored fix.
- **Last-known:** updated only if the batch's newest `recordedAt` is newer than the stored one.
- **Paused device:** `403 TRACKING_PAUSED`, with current settings in `error.details.deviceSettings`. While paused the device MUST stop collecting fixes, stop its periodic worker, and unregister its platform geofences (transitions detected while paused are dropped); fixes recorded **before** the pause MAY still be uploaded after resume. **Resume is pull-based:** while paused the device MUST re-check its settings via `GET /devices` on every app foreground and at least every 6 hours; the `SETTINGS_CHANGED` push (§8.3) is a best-effort accelerator, never the resume mechanism.
- **Fix sources:** on a geofence transition the device SHOULD also record one fix with `source: "geofence"` (so the map has a position matching the event); `source: "manual"` is a user-initiated refresh of the device's own position from the app UI.
- **Piggybacked sync:** every response carries current `deviceSettings` and the geofence config `geofenceEtag`; if the ETag differs from the device's cached one, the device SHOULD `GET /geofences` (§7.1). This bounds config staleness to one sync interval with zero extra polling. For a **family-less caller**, `geofenceEtag` is `"0"` (geofences are family-scoped; there is no config to sync).
- **Group fan-out (side effect):** after last-known is updated, the batch's newest fix is also upserted (same only-newer rule, position-only fields — 002 §2.12) into each of the reporter's **`active`** groups (state per 005 §2.2) — at most `features.limits.maxActiveGroups` extra writes. Paused devices never reach this point (`TRACKING_PAUSED` above).
- **History gate:** the per-fix history append happens **only when the caller has a family**. A family-less user's fixes update last-known and group positions only — group participation never creates durable location history (005 §3).

### 5.2 Live map — `GET /locations/latest`

One call returns the whole family (roster scan + per-member `Devices`/`LastKnown` partition scans, parallelized — 002 §2.4–2.5). Requires a family (§1.5.4) — a family-less caller's live view is the group map (§12.10).

```json
// 200 → data
{ "members": [
    { "userId": "u2", "displayName": "Noor", "devices": [
        { "deviceId": "…", "deviceName": "Noor's phone",
          "lat": 51.0543, "lon": 3.7174, "accuracyM": 15.0,
          "recordedAt": "2026-07-19T09:05:12Z", "receivedAt": "2026-07-19T09:05:14Z",
          "batteryPct": 78, "source": "periodic",
          "trackingEnabled": true, "syncIntervalMinutes": 15,
          "isStale": false } ] } ] }
```

- Members with no registered devices are included with `"devices": []` — every member always appears on the map roster.
- Devices with no report yet are included with `lat`/`lon`/`recordedAt`/`isStale` as `null` — the "no location yet" state, rendered identically by both apps.
- `isStale` MUST be computed server-side as `now − recordedAt > 2 × syncIntervalMinutes` — defined here once so both apps render identically. Note: iOS cannot honor sub-15-minute intervals (000 §O2), so such devices will legitimately show `isStale: true` much of the time.

### 5.3 History — `GET /locations/history`

Query params: `userId` (required), `deviceId` (optional — all the user's devices when omitted), `from`, `to` (required, `YYYY-MM-DD`, inclusive, device-agnostic UTC dates, max span 31 days → else `VALIDATION_FAILED`), `limit` (1–500, default 500), `cursor` (opaque).

```json
// 200 → data
{ "points": [
    { "deviceId": "…", "recordedAt": "…", "lat": 51.05, "lon": 3.71,
      "accuracyM": 12.5, "batteryPct": 78, "source": "periodic" } ],
  "nextCursor": "eyJkIjoi…" }   // null when exhausted
```

Ordered ascending by `recordedAt`. `cursor` is opaque to clients (encoding in 002 §3.3). Requests older than `features.limits.historyDays` → `400 VALIDATION_FAILED`, `details.reason: "beyondRetention"`. `userId` is **not** validated against current membership: a removed member's userId returns their retained history (000: removal keeps historical data); an unknown userId returns an empty result, not an error.

---

## 6. Push-to-locate

Design (000 §D4): requester polls; the instant answer is last-known.

### 6.1 Create — `POST /locate-requests`

```json
// request — exactly one of targetUserId | targetDeviceId
{ "targetUserId": "u2" }
```

- **Target resolution (ordered):** (1) candidates = the target user's devices with `trackingEnabled: true`; target has **no registered devices at all** → `404 DEVICE_NOT_FOUND`, devices exist but **none unpaused** → `403 TRACKING_PAUSED`. (2) Prefer candidates with a valid push token (`pushToken` present and not `pushInvalid`); within the preferred group pick the most-recently-seen. (3) If the chosen device still has no valid token, the request is created as `pushFailed` (§6.2) — the requester still gets last-known. With `targetDeviceId`, steps (2)–(3) apply to that single device (unknown id → `404 DEVICE_NOT_FOUND`; paused → `403 TRACKING_PAUSED`).
- Daily quota: `features.limits.locateRequestsPerDay` per family (UTC day) → `402 LIMIT_EXCEEDED`, `details.limit: "locateRequestsPerDay"`. Only `201`-created requests count toward the quota; coalesced `200`s do not.
- **Coalescing:** if a `pending` request for the same target device exists, it is returned (`200`) instead of creating a new one.

```json
// 201 (created) / 200 (coalesced) → data
{ "requestId": "lr_8Xk2…", "status": "pending",
  "targetUserId": "u2", "targetDeviceId": "…",
  "expiresAt": "2026-07-19T09:06:12Z",          // now + 60 s
  "lastKnown": {                                  // instant answer; null if never reported
    "deviceId": "…", "lat": 51.0543, "lon": 3.7174, "accuracyM": 15.0,
    "recordedAt": "2026-07-19T08:50:12Z" } }
```

Side effect: `LOCATE_REQUEST` push (§8.1) to the target device.

### 6.2 Poll — `GET /locate-requests/{requestId}`

Only the requester may poll (`403 AUTH_FORBIDDEN` otherwise; unknown id → `404 LOCATE_REQUEST_NOT_FOUND`). Clients SHOULD poll every **2 s** until terminal.

```json
// 200 → data
{ "requestId": "lr_…",
  "status": "pending",        // "pending" | "fulfilled" | "expired" | "pushFailed"
  "expiresAt": "…",
  "fix": null }               // §5.1 fix shape (+ deviceId) when fulfilled
```

- Server marks `expired` lazily when polled past `expiresAt`.
- `pushFailed` = FCM rejected the send (bad/unregistered token). UI: "couldn't reach the device — showing last known". The device is marked `pushInvalid` (§4.1).

### 6.3 Fulfill — `POST /locate-requests/{requestId}/fulfill`

Called by the **target device** (`X-Device-Id` MUST equal the request's target, else `403 AUTH_FORBIDDEN`). One high-accuracy fix, same shape as §5.1 fixes, `source` MUST be `"locate"`.

```json
// request
{ "fix": { "fixId": "…-uuid", "recordedAt": "…", "lat": 51.0544, "lon": 3.7170,
           "accuracyM": 4.8, "batteryPct": 77, "source": "locate" } }

// 200 → data
{ "status": "fulfilled" }
```

- Fulfilling past `expiresAt`: `410 LOCATE_REQUEST_EXPIRED` — but the fix is still stored (last-known + history); only the request status is expired. A device receiving a `LOCATE_REQUEST` push more than **10 minutes** past its `expiresAt` SHOULD ignore it (no GPS burn for a stale request); within that window it SHOULD still take the fix and fulfill.
- Fulfill also updates last-known and appends to history exactly like a §5.1 report (idempotent on `fixId`).
- A paused target MAY still fulfill (the parent asked): `TRACKING_PAUSED` does **not** apply here. Rationale: pause stops *periodic* surveillance; an explicit locate is user-initiated and quota-limited.

---

## 7. Geofences

### 7.1 Get config — `GET /geofences`

Devices sync the **whole document** (they must re-register all platform geofences on any change). Supports `If-None-Match` → `304 Not Modified` (empty body).

```json
// 200 → data   (+ ETag response header)
{ "version": 4,
  "geofences": [
    { "geofenceId": "gf_home", "name": "Home",
      "lat": 51.0543, "lon": 3.7174, "radiusM": 150,
      "icon": "home",                                  // free string ≤ 30, client-rendered
      "notifyOnEnter": true, "notifyOnExit": true } ] }
```

A family with no config yet gets `{ "version": 0, "geofences": [] }` with `ETag: "0"`.

`notifyOnEnter`/`notifyOnExit` control **server-side notification fan-out only** (§7.3, §8.2). Devices MUST register and report **all** transitions for every configured geofence regardless of the flags — history stays complete, and flag changes take effect instantly without any device re-registration.

### 7.2 Replace config — `PUT /geofences` (parent)

Full-document replace. `If-Match` header REQUIRED (`"0"` sentinel for the first write; missing header → `400 VALIDATION_FAILED`; stale → `409 GEOFENCE_VERSION_CONFLICT`, client re-GETs and merges).

```json
// request — the geofences array only; version is server-managed
{ "geofences": [ { "geofenceId": "gf_home", "name": "Home", "lat": 51.0543, "lon": 3.7174,
                   "radiusM": 150, "icon": "home", "notifyOnEnter": true, "notifyOnExit": true } ] }

// 200 → data (+ new ETag header)
{ "version": 5, "geofences": [ /* as stored */ ] }
```

Validation: ≤ `features.limits.maxGeofences` entries (→ `402 LIMIT_EXCEEDED`, `details.limit: "maxGeofences"`); `radiusM` ∈ [100, 5000] (platform accuracy floor / sanity cap); `name` 1–50 chars; `geofenceId` slugs unique. Side effect: `GEOFENCE_CONFIG_CHANGED` push (§8.4) to all family devices.

### 7.3 Report geofence events — `POST /geofence-events`

Sent by the device that natively detected the transition. Batch of 1–20 events.

```json
// request
{ "events": [
    { "eventId": "…-uuid", "geofenceId": "gf_home",
      "transition": "enter",                    // "enter" | "exit"
      "recordedAt": "2026-07-19T15:03:22Z" } ] }

// 200 → data  (same piggyback fields as §5.1)
{ "accepted": 1, "duplicates": 0,
  "deviceSettings": { "syncIntervalMinutes": 15, "trackingEnabled": true },
  "geofenceEtag": "\"0x8DC5F3A9B2C1D40\"" }
```

- Idempotent per event on `(deviceId, eventId)` (replays counted in `duplicates`).
- Unknown `geofenceId` (stale device config): event is **accepted and stored** with `geofenceName: null`, no notification fan-out — the device SHOULD notice the `geofenceEtag` mismatch in the response and re-sync config.
- Paused device → `403 TRACKING_PAUSED`.
- Side effect per accepted event: history append **always**; `GEOFENCE_EVENT` push (§8.2) to **all family devices except the reporting one**, sent **only if** the geofence's `notifyOnEnter`/`notifyOnExit` flag for this transition is `true` (§7.1).

### 7.4 Geofence event history — `GET /geofence-events`

Query: `from`, `to` (required, as §5.3), `userId` (optional filter), `limit` (1–500, default 500), `cursor`.

```json
// 200 → data
{ "events": [
    { "userId": "u2", "deviceId": "…", "geofenceId": "gf_home", "geofenceName": "Home",
      "lat": 51.0543, "lon": 3.7174, "radiusM": 150,
      "transition": "enter", "recordedAt": "2026-07-19T15:03:22Z", "receivedAt": "…" } ],
  "nextCursor": null }
```

Geofence name and coordinates are frozen into the event at write time (002 §3.2), so history stays plottable after a geofence is moved, renamed, or deleted; all four (`geofenceName`, `lat`, `lon`, `radiusM`) are `null` for events whose `geofenceId` was unknown at write time (§7.3). The `historyDays` window (`beyondRetention` error) and the removed-member `userId` rule apply exactly as in §5.3.

---

## 8. Push message catalog (FCM HTTP v1)

All pushes go through FCM v1 (`projects/<project>/messages:send`); FCM routes to APNs for iOS devices. Common rule: every message carries `data.type` as the discriminator; all `data` values are strings (FCM constraint — clients parse).

### 8.1 `LOCATE_REQUEST` (to target device — high priority, data-only)

```json
{ "message": { "token": "<deviceToken>",
  "android": { "priority": "high" },
  "apns": { "headers": { "apns-priority": "5", "apns-push-type": "background" },
            "payload": { "aps": { "content-available": 1 } } },
  "data": { "type": "LOCATE_REQUEST", "requestId": "lr_…",
            "requestedByName": "Eric", "expiresAt": "2026-07-19T09:06:12Z" } } }
```

iOS (000 §O1): the message above is the **v1-normative** send; on iOS it arrives as a budgeted/coalesced background push — best-effort by design. The reliable mechanism, once Apple grants the Location Push entitlement, is a **direct APNs send — not FCM** (FCM cannot address location push tokens): token-based `.p8` auth, topic `<bundleId>.location-query`, headers `apns-push-type: location`, `apns-priority: 10`, targeting the device's `locationPushToken` (§4.1, obtained via `CLLocationManager.startMonitoringLocationPushes`), carrying the same `data` fields in the APNs payload. That path adds one APNs key credential to the backend when it lands (tracked in 000 §O1); nothing about it is implemented in v1.

### 8.2 `GEOFENCE_EVENT` (to all family devices except reporter — notification + data)

```json
{ "message": { "token": "…",
  "notification": { "title": "Noor arrived at Home" },        // server-composed English (000 §O8); NO body —
                                                              //   the notification's own timestamp conveys the
                                                              //   time in the recipient's locale/zone
  "android": { "priority": "normal" },
  "apns": { "headers": { "apns-priority": "5", "apns-push-type": "alert" },
            "payload": { "aps": { "mutable-content": 1 } } },
  "data": { "type": "GEOFENCE_EVENT", "userId": "u2", "displayName": "Noor",
            "geofenceId": "gf_home", "geofenceName": "Home",
            "transition": "enter", "recordedAt": "2026-07-19T15:03:22Z" } } }
```

Title template (normative): `"<displayName> arrived at <geofenceName>"` / `"<displayName> left <geofenceName>"` — no time in the text (the server cannot know recipients' time zones). `mutable-content: 1` lets an iOS Notification Service Extension re-render the alert locally from `data` (000 §O8); Android clients MAY do the same in their FCM handler.

### 8.3 `SETTINGS_CHANGED` (to the affected device — data-only, normal priority)

```json
{ "message": { "token": "…",
  "android": { "priority": "normal" },
  "apns": { "headers": { "apns-priority": "5", "apns-push-type": "background" },
            "payload": { "aps": { "content-available": 1 } } },
  "data": { "type": "SETTINGS_CHANGED",
            "syncIntervalMinutes": "30", "trackingEnabled": "false" } } }
```

Always carries the **complete current values of both fields** — full state, never a delta — so the message is idempotent and reorder-safe; clients MUST apply both. The device reacts immediately: reschedules its worker, pauses, or resumes. Delivery is best-effort; the guaranteed pickup paths are the §5.1 piggyback (active devices) and the §5.1 paused-device settings poll.

### 8.4 `GEOFENCE_CONFIG_CHANGED` (to all family devices — data-only, normal priority)

```json
{ "message": { "token": "…",
  "android": { "priority": "normal" },
  "apns": { "headers": { "apns-priority": "5", "apns-push-type": "background" },
            "payload": { "aps": { "content-available": 1 } } },
  "data": { "type": "GEOFENCE_CONFIG_CHANGED", "etag": "\"0x8DC…\"" } } }
```

Device responds by `GET /geofences` with `If-None-Match` and re-registers platform geofences.

### 8.5 Token hygiene

FCM responses indicating an invalid/unregistered token (`UNREGISTERED`, `INVALID_ARGUMENT` on token) MUST mark the device `pushInvalid: true` (§4.1). Any successful `POST /devices` with a fresh token clears the flag.

### 8.6 Sending credential

FCM v1 send requires a Google service account (`FCM_SERVICE_ACCOUNT_JSON` app setting; OAuth2 `https://www.googleapis.com/auth/firebase.messaging`). This is the only stored credential in the system (000 §O6).

### 8.7 Reserved group message types (not sent in v1)

The `data.type` values `GROUP_MEMBER_JOINED` and `GROUP_ENDING_SOON` are **reserved** for future group notifications (005 §5, 000 §O14). No v1 backend sends them; clients MUST ignore unknown `data.type` values (they already must, §1.1 forward compatibility).

---

## 9. Entitlements & `features`

Shape (present in every success envelope):

```json
{ "subscriptionStatus": "free",
  "limits": { "maxDevices": 10, "maxGeofences": 20, "historyDays": 90,
              "minSyncIntervalMinutes": 5, "locateRequestsPerDay": 100,
              "maxActiveGroups": 5, "maxGroupMembers": 200,
              "maxGroupDurationDays": 30, "groupGraceDays": 7,
              "exportsPerDay": 3 },
  "flags": { "pushToLocate": true, "geofencing": true, "historyReplay": true, "groups": true } }
```

- Derived **server-side only** from `PLAN_MATRIX[subscriptionStatus]` (a constant in `backend/src/domain/plan.ts`). Clients never send entitlement data.
- `"active"` currently mirrors `"free"` — it is a reserved placeholder; changing plan benefits later = editing the matrix, nothing else.
- The `features` envelope always reflects the **caller**: their family's entitlement when they have one, else an implicit `"free"` (family-less users have no `Entitlements` row — 002 §2.6).
- **Group capacity is governed by the owner's plan:** `maxGroupMembers` is resolved from the group **owner's** entitlement at join time (§12.6) — the future "owner upgrades → bigger group" story without snapshotting limits into storage. The caller-scoped group limits (`maxActiveGroups`, `maxGroupDurationDays`) enforce against the caller's own `features`.
- **Every** limit enforcement point (device cap §4.1, geofence cap §7.2, history window §5.3/§7.4, locate quota §6.1, interval floor §1.4/§4.3, group caps §12.1/§12.4/§12.6, export quota §13.1) reads this object — never a literal.
- Plan-cap violations (`maxDevices`, `maxGeofences`, `locateRequestsPerDay`, `minSyncIntervalMinutes`, `maxActiveGroups`, `maxGroupDurationDays`, `exportsPerDay`) use HTTP **402** `LIMIT_EXCEEDED` with `details.limit: "<limits key>"` — the single future upsell hook. Two deliberate exceptions: the history window is `400 VALIDATION_FAILED`, `details.reason: "beyondRetention"` (§5.3/§7.4), because it bounds a query, not a plan action; and group capacity is `409 GROUP_FULL` (§12.6), because the joiner hitting it isn't the upsell target — the owner's plan governs capacity.
- **Usage increment rules** (stored per family/day — per user/day for family-less callers, 002 §2.9): `apiCalls` +1 per authenticated request (any endpoint, once auth succeeds); `locationBatches` +1 per accepted non-duplicate batch; `fixes` + accepted-fix count; `locateRequests` +1 per `201`-created request only (coalesced `200`s and rejections excluded — this metric feeds the §6.1 quota); `geofenceEvents` + accepted-event count; `exports` +1 per successful §13.1 download (feeds the `exportsPerDay` quota; counted against the **caller**, also when exporting another member).

---

## 10. Error-code catalog (complete — code may not be invented elsewhere)

| HTTP | `code` | When | `details` |
|---|---|---|---|
| 401 | `AUTH_MISSING_TOKEN` | No/malformed `Authorization` header | — |
| 401 | `AUTH_INVALID_TOKEN` | Signature/`iss`/`aud`/`iat` check failed | — |
| 401 | `AUTH_TOKEN_EXPIRED` | `exp` in the past (client: refresh & retry once) | — |
| 403 | `AUTH_FORBIDDEN` | Valid user, insufficient role / not requester / wrong device | — |
| 403 | `TRACKING_PAUSED` | Paused device reports (§5.1, §7.3) or locate target paused (§6.1) | `{ "deviceSettings": { … } }` on §5.1/§7.3, so a surviving call re-syncs settings |
| 404 | `PROFILE_NOT_FOUND` | Caller has no profile (endpoints outside the §1.5.3 bootstrap allowance) | — |
| 404 | `FAMILY_NOT_FOUND` | Caller has a profile but no family (family-scoped endpoints, §1.5.4) | — |
| 404 | `MEMBER_NOT_FOUND` | `{userId}` not in caller's family (§3.5–3.6) / not in the addressed group (§12.9) | — |
| 404 | `DEVICE_NOT_FOUND` | Unknown `deviceId` / `X-Device-Id` not owned by caller | — |
| 404 | `LOCATE_REQUEST_NOT_FOUND` | Unknown `requestId` (or not in caller's family) | — |
| 404 | `GROUP_NOT_FOUND` | Unknown `groupId`, caller not a member of it (masked, §12), or group already swept | — |
| 409 | `FAMILY_ALREADY_MEMBER` | Create/join while already in a family | — |
| 409 | `GEOFENCE_VERSION_CONFLICT` | `If-Match` mismatch on §7.2 | `{ "currentEtag": "…" }` |
| 409 | `GROUP_ALREADY_MEMBER` | Join a group the caller is already in (§12.6) | — |
| 409 | `GROUP_FULL` | Roster at the owner-plan `maxGroupMembers` cap (§12.6, §9) | `{ "max": 200 }` |
| 410 | `INVITE_EXPIRED` | Code past `expiresAt` | — |
| 410 | `LOCATE_REQUEST_EXPIRED` | Fulfill after expiry (§6.3 — fix still stored) | — |
| 410 | `GROUP_EXPIRED` | Operation on a group past its usable life for that path (matrix in 005 §2.3, §12) | — |
| 400 | `INVITE_INVALID` | Unknown invite code | — |
| 400 | `INVITE_ALREADY_USED` | Single-use code already consumed | — |
| 400 | `GROUP_CODE_INVALID` | Unknown or rotated group join code (§12.6) | — |
| 400 | `VALIDATION_FAILED` | Any request-schema violation | `{ "fields": ["fixes[3].recordedAt"], "reason?": "lastParent" \| "beyondRetention" \| "deviceIdInUse" \| "ownerCannotLeave" \| … }` |
| 400 | `LOCATION_BATCH_TOO_LARGE` | > 100 fixes (§5.1) | `{ "max": 100 }` |
| 402 | `LIMIT_EXCEEDED` | Plan limit hit | `{ "limit": "maxDevices" \| "maxGeofences" \| "locateRequestsPerDay" \| "minSyncIntervalMinutes" \| "maxActiveGroups" \| "maxGroupDurationDays" \| "exportsPerDay" }` |
| 429 | `RATE_LIMITED` | Per-user throttle (reserved; not enforced in v1) | `{ "retryAfterSeconds": 30 }` |
| 500 | `INTERNAL_ERROR` | Unhandled failure; never leaks internals | — |
| 503 | `PUSH_DELIVERY_FAILED` | Reserved. The locate flow reports push failure via `status: "pushFailed"` (§6.2), never via this error; geofence fan-out failures are silent best-effort. Kept for future endpoints where a synchronous push IS the operation. | — |

Envelope format: §1.3. `message` is for logs/debugging only; clients map `code` → localized UX.

---

## 11. Test checklist (conforming backend)

- Envelope: every success includes `features`; every error matches §1.3 with a `requestId`; §3.6/§12.5/§12.8/§12.9/§13.2/§13.3 return bare `204`; §13.1 returns the unenveloped export document.
- Auth: each 401 variant; role matrix per §1.6; no-family allowance (§1.5.3); pause enforcement on §5.1/§7.3 (with `deviceSettings` in `details`) but **not** §6.3.
- Family: create → creator parent + entitlements `free`; double-create/join → `FAMILY_ALREADY_MEMBER`; invite single-use under concurrency; expiry; last-parent protection.
- Devices: defaults on first registration; upsert preserves parent-managed settings; device cap counts only new registrations; owner-PATCH restricted to `pushToken`.
- Locations: batch idempotency (`batchId` replay; marker only on accept); batch immutability + split rules; empty-batch rejection; clock-skew rejection; last-known only-newer rule; piggybacked `deviceSettings` + `geofenceEtag`; batch size cap.
- Latest: whole family incl. device-less members (`devices: []`) and never-reported devices (all-`null` incl. `isStale`); `isStale` formula.
- History: date-span cap, retention window (`historyDays`), cursor round-trip, ascending order, `deviceId` merge.
- Locate: instant `lastKnown`; ordered target resolution (§6.1) incl. no-devices → 404 and all-paused → 403; coalescing (excluded from quota); quota; poll authorization; lazy expiry; fulfill after expiry stores fix but returns 410; `pushFailed` path marks `pushInvalid`.
- Geofences: ETag 304/409 flows; `"0"` sentinel create; validation caps; `notifyOnEnter`/`notifyOnExit` fan-out filtering (history always stored); unknown-`geofenceId` event acceptance without fan-out; event idempotency.
- Features: limits read from `PLAN_MATRIX` only (mutation testing should kill hardcoded-literal mutants).
- Profiles: the four §1.5.3 bootstrap endpoints create a profile; `PROFILE_NOT_FOUND` everywhere else without one; family-less caller on family-scoped endpoints → `FAMILY_NOT_FOUND`; family-less §4.2 own-devices response and §4.3 full-field own-device PATCH.
- Groups (§12; full matrix in 005 §7): lifecycle × policy enforcement; owned+joined `maxActiveGroups` count; owner-plan `GROUP_FULL`; join/rotate/kick/leave code paths; `GROUP_NOT_FOUND` masking for non-members; §5.1 fan-out (active groups only, position-only fields, only-newer) and the family-less history gate; sweeper per-policy deletion + idempotent re-run.
- Privacy (§13; full matrix in 008 §9): export coverage/authorization/quota; account-delete erasure completeness, ordering (devices first, profile last), crash-retry idempotency, no-profile no-op, last-parent/sole-member cascade; family-delete coverage, member survival, invite revocation + §3.4 fail-closed.

---

## 12. Groups (temporary)

Product model, lifecycle, and privacy guarantees are normative in [005](005-temporary-groups.md); this section owns the wire shapes. Group state (`active` | `ended` | `archived`) is derived per 005 §2.2 and echoed in responses — `expired` is never serialized: expired groups are filtered from §12.2 and answer `410 GROUP_EXPIRED` (post-sweep: `404 GROUP_NOT_FOUND`) elsewhere, per the 005 §2.3 matrix. On every `{groupId}` route, a caller who is not a member receives `404 GROUP_NOT_FOUND`, indistinguishable from a nonexistent group.

### 12.1 Create group — `POST /groups`

Any authenticated user. Bootstraps a profile if the caller has none (§1.5.3) — `displayName` is REQUIRED then, optional otherwise (defaults to the profile's). The caller becomes `owner`. The caller's non-expired memberships (owned + joined) MUST be `< features.limits.maxActiveGroups` (→ `402 LIMIT_EXCEEDED`, `details.limit: "maxActiveGroups"`).

```json
// request
{ "name": "Festival crew", "endsAt": "2026-08-02T22:00:00Z",
  "expiryPolicy": "delete", "displayName": "Eric" }
// name 1–50 chars; expiryPolicy ∈ {delete, grace, archive} (005 §2.1);
// endsAt ≥ now + 1h (else 400 VALIDATION_FAILED) and ≤ now + limits.maxGroupDurationDays
//   (else 402 LIMIT_EXCEEDED, details.limit: "maxGroupDurationDays"); displayName 1–30 chars

// 201 → data
{ "groupId": "grp_9J2Kq7Lm3NpR5sTvWxYz", "name": "Festival crew",
  "endsAt": "2026-08-02T22:00:00Z", "expiryPolicy": "delete", "state": "active",
  "role": "owner", "memberCount": 1, "code": "7F3K9QRZ",
  "createdAt": "2026-07-21T10:00:00Z" }
```

### 12.2 List my groups — `GET /groups`

Caller needs a profile. Expired groups are filtered out; `ended`/`archived` ones appear with their state.

```json
// 200 → data
{ "groups": [
    { "groupId": "grp_…", "name": "Festival crew", "endsAt": "…", "expiryPolicy": "delete",
      "state": "active", "role": "owner", "memberCount": 7, "code": "7F3K9QRZ" } ] }
```

`code` is present for **every** member (any member may recruit — 005 §1); it is `null` once the group is past `endsAt` (the code row is deleted, 005 §2.3).

### 12.3 Get group — `GET /groups/{groupId}` (group member)

The §12.2 item plus the roster. During `grace` (`state: "ended"`), non-owner members receive the item with `"members": null` (roster hidden, 005 §2.3); the owner and `archived` groups get the full roster.

```json
// 200 → data
{ "groupId": "grp_…", "name": "Festival crew", "endsAt": "…", "expiryPolicy": "delete",
  "state": "active", "role": "member", "memberCount": 7, "code": "7F3K9QRZ",
  "createdAt": "…",
  "members": [
    { "userId": "u1", "displayName": "Eric", "role": "owner",  "joinedAt": "…" },
    { "userId": "u9", "displayName": "Noor", "role": "member", "joinedAt": "…" } ] }
```

### 12.4 Update group — `PATCH /groups/{groupId}` (owner)

```json
// request — at least one field
{ "name": "Festival crew 2026", "endsAt": "2026-08-03T22:00:00Z" }
```

- `endsAt` MUST be `> now` and `≤ now + limits.maxGroupDurationDays` (→ `402`, `details.limit: "maxGroupDurationDays"`); as a convenience, `endsAt ≤ now + 5 min` means "end the group now". Extending a `grace`-state (`ended`) group **reactivates** it (005 §2.2). Not allowed on `archived` (→ `410 GROUP_EXPIRED`).
- `200` → data: the updated §12.2 item shape.

### 12.5 Delete group — `DELETE /groups/{groupId}` (owner)

`204` (empty body). Immediate, synchronous hard delete of everything (members, code, locations, indexes — 005 §2.4), in any state, regardless of policy.

### 12.6 Join group — `POST /groups/join`

Any authenticated user. Bootstraps a profile if absent (§1.5.3 — `displayName` REQUIRED then; otherwise optional, defaulting to the profile's). The `displayName` in the request becomes the caller's **per-group** display name (005 §1).

```json
// request
{ "code": "7f3k-9qrz", "displayName": "Noor" }

// 200 → data
{ "groupId": "grp_…", "name": "Festival crew", "endsAt": "…", "expiryPolicy": "delete",
  "state": "active", "role": "member", "memberCount": 8, "code": "7F3K9QRZ" }
```

Errors: unknown/rotated code → `400 GROUP_CODE_INVALID`; group past `endsAt` → `410 GROUP_EXPIRED`; already a member → `409 GROUP_ALREADY_MEMBER`; roster at the **owner's** plan `maxGroupMembers` (§9) → `409 GROUP_FULL`, `details: { "max": 200 }`. The membership insert is conditional; the capacity check is best-effort under concurrency (same accepted class as the §4.1 device cap).

### 12.7 Rotate join code — `POST /groups/{groupId}/code/rotate` (owner)

The old code stops working instantly; there is always exactly one live code per active group.

```json
// 200 → data
{ "code": "9XPT4WKA", "rotatedAt": "2026-07-21T10:05:00Z" }
```

### 12.8 Leave group — `POST /groups/{groupId}/leave` (group member)

`204` (empty body). Removes the caller's membership and their group position immediately. Works in any non-expired state (clearing an `archived` memento is allowed). The **owner cannot leave** (no ownership transfer in v1, 000 §O15) → `400 VALIDATION_FAILED`, `details.reason: "ownerCannotLeave"` — the owner ends (§12.4) or deletes (§12.5) instead.

### 12.9 Kick member — `DELETE /groups/{groupId}/members/{userId}` (owner)

`204` (empty body). Same removals as §12.8, applied to `{userId}`; their position disappears from the group map immediately. Unknown/non-member `{userId}` → `404 MEMBER_NOT_FOUND`. The owner cannot kick themselves → `400 VALIDATION_FAILED`, `details.reason: "ownerCannotLeave"`.

### 12.10 Group live map — `GET /groups/{groupId}/locations/latest` (group member)

Only on `active` groups — `ended`/`archived`/expired → `410 GROUP_EXPIRED` (005 §2.3). One partition scan (002 §2.12). Every member appears (roster parity with §5.2); `location: null` = no position yet. **Position-only** (005 §3): no `deviceId`, `deviceName`, `batteryPct`, `source`, altitude/speed/bearing.

```json
// 200 → data
{ "members": [
    { "userId": "u1", "displayName": "Eric", "role": "owner",
      "location": { "lat": 51.0543, "lon": 3.7174, "accuracyM": 15.0,
                    "recordedAt": "2026-07-21T09:58:00Z", "receivedAt": "2026-07-21T09:58:02Z",
                    "isStale": false } },
    { "userId": "u9", "displayName": "Noor", "role": "member", "location": null } ] }
```

`isStale` uses the §5.2 formula, computed from the `syncIntervalMinutes` frozen into the group position at write time (002 §2.12) — it reflects the reporting device's interval as of its last fix.

---

## 13. Privacy: export & deletion

Concepts, guarantees, and the web deletion surface are normative in [008](008-privacy-endpoints.md); this section owns the wire shapes. Storage coverage and deletion ordering: 002 §4.2.

### 13.1 Export — `GET /export`

Query: `userId` (optional — another **current member of the caller's family**, parent-only; defaults to the caller). Caller needs a profile (`404 PROFILE_NOT_FOUND` otherwise). A non-parent supplying `userId` ≠ self → `403 AUTH_FORBIDDEN`; a parent supplying a non-member → `404 MEMBER_NOT_FOUND`. Quota: `features.limits.exportsPerDay` per caller per UTC day (→ `402 LIMIT_EXCEEDED`, `details.limit: "exportsPerDay"`).

**Response (`200`) is the export document itself — NOT enveloped** (§1.3 exception; there is no `features` object): `Content-Type: application/json; charset=utf-8`, `Content-Disposition: attachment; filename="findly-export-<userId>-<yyyy-MM-dd>.json"`, and **`Cache-Control: no-store`** (REQUIRED — without it an intermediary or the client's own HTTP cache silently persists a second plaintext copy of the subject's full history; see 008 §3.1). Location history spans the **full physical retention window** (002 §4), deliberately beyond `features.limits.historyDays` (008 §3). No pagination; the document is size-bounded by retention at family scale.

```json
{ "formatVersion": 1,
  "generatedAt": "2026-07-25T14:00:00Z",
  "subject": { "userId": "<uid>", "displayName": "Noor" },
  "family": { "familyId": "fam_…", "familyName": "Wauters",
              "role": "member", "joinedAt": "…" },          // null when family-less
  "devices": [ { /* §4.1 response object — push tokens never included */ } ],
  "lastKnown": [ { "deviceId": "…", "lat": 51.05, "lon": 3.71, "accuracyM": 12.5,
                   "batteryPct": 78, "recordedAt": "…", "receivedAt": "…", "source": "periodic" } ],
  "locationHistory": [ { /* 002 §3.2 history line + "deviceId" */ } ],
  "geofenceEvents": [ { /* 002 §3.2 event line — subject's own lines only */ } ],
  "groups": [ { "groupId": "grp_…", "name": "Festival crew", "role": "member",
                "displayName": "Noor", "joinedAt": "…", "state": "active", "endsAt": "…" } ],
  "groupPositions": [ { "groupId": "grp_…", "lat": 51.05, "lon": 3.71,
                        "accuracyM": 15.0, "recordedAt": "…" } ],
  "usage": [ { "date": "2026-07-25", "metric": "apiCalls", "count": 41 } ],   // uid-keyed rows only (008 §2)
  "providerData": { "firebaseAuthentication":
      "Your phone number and sign-in metadata are held by Firebase Authentication, not by Findly; they are deleted when your account is deleted." } }
```

Success increments usage metric `exports` (§9).

### 13.2 Delete my account — `DELETE /users/me`

`204` (empty body). Available to **every** authenticated user — including one with **no profile** (idempotent no-op, §1.5.3). Synchronous, irreversible erasure of every subject-scoped item (coverage table: 008 §2; ordering + crash-retry semantics: 002 §4.2 — devices first, profile row last). Owned groups are hard-deleted with §12.5 semantics; joined groups are left with §12.8 semantics. **Cascade rule (008 §4.2):** when the caller's departure would leave their family without any parent (last parent, or sole member), the call performs the full §13.3 family deletion inline; otherwise the family survives and only the caller is erased.

After `204`, the client MUST delete the Firebase Auth user via the SDK (008 §1.3) — the backend never touches Firebase accounts. The endpoint is re-callable until clean; clients SHOULD retry on 5xx/timeout.

### 13.3 Delete my family — `DELETE /families/me` (parent)

`204` (empty body). Synchronous, irreversible deletion of every family-scoped item — identity, roster, entitlements, usage, locate requests, invites (revoked via the 002 §2.1 index rows), geofence config, and **all** history/event blobs for every member (coverage: 008 §2; ordering: 002 §4.2 — other members' profiles flip family-less first, caller's profile last). Member **accounts survive** family-less (008 §5.2): their devices, last-known, and groups are untouched; there is no push notification in v1 — members land on `404 FAMILY_NOT_FOUND` → the family-less home. Re-callable until clean.

## Open questions

None — platform delivery risks are tracked in 000 §Open Items (O1, O2); deferred group matters in 000 §Open Items (O13–O16).
