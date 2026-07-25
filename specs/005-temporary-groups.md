# 005 — Temporary groups

## Goal

A temporary community "find me": any signed-in user can create a **group** with an **end date** (a festival weekend, a holiday week), share a multi-use **join code/link**, and every member sees every other member's live position on a group map until the group ends and its data is deleted. Groups are **independent of families** — a user has at most one family plus several groups, or no family at all. This spec owns the group concept, lifecycle, privacy guarantees, and limits; wire shapes live only in [001 §12](001-api-contract.md), storage layouts only in [002 §2.10–2.13](002-storage-schema.md).

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively.

## 1. Concepts & model

- A **group** has: `groupId` (`grp_` + 20, 001 §1.4), a name, an **owner** (its creator), an end instant `endsAt`, an **expiry policy** (§2), and one current multi-use **join code** (same 8-char Crockford format and normalization as family invites, 001 §1.4).
- **Roles:** `owner` | `member`. The owner manages the group (rename, extend/shorten, rotate code, kick, delete); members see the roster + map and can leave. There is exactly one owner and no ownership transfer in v1 (000 §O15).
- **Membership is per-user, not per-family.** Joining requires only the code. A user's concurrent non-expired memberships (owned + joined) are capped by `features.limits.maxActiveGroups`; a group's size is capped by the **owner's** plan's `maxGroupMembers` (001 §9).
- **Per-group `displayName`:** each membership carries its own display name (defaulting to the profile's) — "Mom" at home can be "Eric" at the festival. Chosen at create/join, not editable in v1.
- **Family-less users are first-class:** creating or joining a group is a profile-bootstrapping action (001 §1.5). A family-less user can register devices, report locations, and use groups; family-scoped features (family map, history, geofences, locate) require a family (001 §1.5.4).
- The join code is visible to **all members** (anyone can recruit); only the owner can rotate it. Rotating instantly invalidates the old code.

## 2. Lifecycle & expiry policies

### 2.1 Policies (chosen at creation, immutable afterwards)

| `expiryPolicy` | At `endsAt` | Afterwards |
|---|---|---|
| `delete` | Group becomes unreadable (`GROUP_EXPIRED`) | Everything is physically deleted by the sweeper (§2.4) within ~24 h |
| `grace` | Locations + joinability die; group is listed as `ended`; **owner may reactivate** by extending `endsAt` | At `endsAt + limits.groupGraceDays`: physically deleted like `delete` |
| `archive` | Locations + joinability die | Roster stays visible as a memento until the owner deletes the group or a member leaves their row behind; location data is deleted by the sweeper within ~24 h |

Plain-language promise per policy (clients MUST show this at creation, 003/004):

- **delete** — "When the group ends, everything about it disappears."
- **grace** — "When the group ends it goes read-only for a few days so the owner can revive it; then everything disappears."
- **archive** — "When the group ends, everyone's locations are deleted; the member list stays as a keepsake."

### 2.2 Derived state (nothing stored)

Group state is a pure function — never a stored column, so there are no transition writes and no drift:

```
state(now, endsAt, policy):
  now < endsAt                                   → "active"
  policy = delete,  now ≥ endsAt                 → expired    (lazy 410 → swept → 404)
  policy = grace,   endsAt ≤ now < graceUntil    → "ended"    (owner may reactivate)
  policy = grace,   now ≥ graceUntil             → expired    (lazy 410 → swept → 404)
  policy = archive, now ≥ endsAt                 → "archived"

graceUntil = endsAt + limits.groupGraceDays
```

Reactivation during grace = `PATCH endsAt` to a future instant (001 §12.4) — state flips back to `active` with zero bookkeeping. `expired` is never serialized in a response; expired groups are filtered from lists and answer `410 GROUP_EXPIRED` (then `404 GROUP_NOT_FOUND` once swept) on direct access.

### 2.3 Lazy enforcement matrix (normative; wire behavior in 001 §12)

| Path | `active` | `ended` (grace) | `archived` | expired |
|---|---|---|---|---|
| appears in `GET /groups` | yes | yes | yes | filtered out |
| `GET /groups/{id}` | yes | owner: full; member: meta only, **no roster** | yes (roster memento) | `410` / post-sweep `404` |
| `GET /groups/{id}/locations/latest` | yes | `410 GROUP_EXPIRED` | `410 GROUP_EXPIRED` | `410` / `404` |
| `POST /groups/join` | yes | `410 GROUP_EXPIRED` | `410 GROUP_EXPIRED` | `400 GROUP_CODE_INVALID` (code row gone) |
| location ingest fan-out (001 §5.1) | yes | no | no | no |
| `PATCH` `endsAt` (owner) | yes | yes (reactivate) | no (`410`) | no |
| `POST .../code/rotate` (owner) | yes | yes | yes | `410` / `404` |
| `leave` / kick / owner `DELETE`¹ | yes | yes | yes | `410` / `404` |

Grace hides the roster from non-owner members (the group is over; the owner sees it to decide on reactivation) — the design intent is "read-only and fading", not "still a group".

Rotate is gated like leave/kick rather than like `PATCH`: allowed on `active`/`ended` (grace)/`archived`, rejected only once truly `expired` (`410`, or `404` once swept) — not blocked on `archived` the way `PATCH endsAt` is. Rationale: rotating a code doesn't conflict with any archived-specific invariant the way extending `endsAt` would (there is no "reactivate archived" concept to protect against); it's a plain code-management action, same category as leave/kick's plain membership-management actions.

¹ Owner `DELETE` is a carve-out that does **not** follow this row's `expired` column: per §12.5, §2.4 above, and 002 §4.1's sweeper description, owner `DELETE` performs the full hard delete "in any state, regardless of policy" — including a not-yet-swept `expired` group. It works whenever `Groups.meta` still exists, full stop; only `leave`/kick are actually gated on `expired` (→ `410`/`404`). Read this row as "leave/kick behave exactly as shown; owner `DELETE` also succeeds on `expired`, uniquely among the three."

### 2.4 Physical deletion — the sweeper

A **daily timer-triggered function** (the project's first; domain logic pure and mutation-tested, function file thin) walks the `GroupExpiry` date-bucket index (002 §2.13) for buckets `[today − 45 days … today]` — the 45-day window generously covers `groupGraceDays` plus any outage backlog; it never scans a full table. Per row it re-reads `Groups.meta` and acts by policy (002 §4): re-buckets if the owner extended; deletes locations + code at `endsAt` (grace/archive); hard-deletes the whole group (meta, members, code, locations, reverse-index rows) at the policy's deletion point, expiry row last. Every delete swallows 404s — a crashed run is safely re-run (idempotent by construction).

**Privacy guarantee (normative):** group location data is **API-unreadable from `endsAt`** (lazy checks, §2.3) and **physically deleted within ~24 h** of the policy's deletion point. Owner `DELETE /groups/{id}` performs the full hard delete **inline and synchronously**, in any state.

## 3. Location sharing

- **Live-only.** The group map shows each member's single most recent position. There is **no group location history**, and group participation MUST NOT create durable location history for anyone: the 001 §5.1 history append happens only when the reporting caller has a family, and group positions live only in the group's own storage partition (002 §2.12) where deletion is a self-contained partition wipe.
- **Position-only.** A group member sees: display name, role, position (`lat`/`lon`/`accuracyM`), freshness (`recordedAt`/`receivedAt`/`isStale`) — and deliberately **not** `deviceId`, `deviceName`, `batteryPct`, `source`, altitude/speed/bearing. Group members may be casual acquaintances; device and battery detail stays family-only (product-owner decision, 2026-07-21).
- **Fan-out on write** (000 §D12): when a location batch is accepted, the newest fix is also upserted (only-newer rule) into each of the reporter's **active** groups — at most `maxActiveGroups` extra writes per batch — so a group map read stays one partition scan. Details in 001 §5.1 / 002 §2.12.
- Pause semantics: `trackingEnabled` stays **device-global** (001 §4.3) — a paused device reports nowhere, family and groups alike. There is no per-group pause in v1 (000 §O13); the way to stop sharing with one group is to **leave** (rejoin later with the code).

## 4. Limits (001 §9; values live in `PLAN_MATRIX`, never at call sites)

| Limit | Free value | Enforced at |
|---|---|---|
| `maxActiveGroups` | 5 | group create (001 §12.1) — counts the caller's non-expired memberships, owned + joined |
| `maxGroupMembers` | 200 | join (001 §12.6) — governed by the **owner's** plan, resolved at join time |
| `maxGroupDurationDays` | 30 | create + `PATCH endsAt` — `endsAt` ≤ now + this horizon |
| `groupGraceDays` | 7 | derived `graceUntil` for `grace`-policy groups |

`flags.groups` gates the whole feature. Group-capacity overflow is `409 GROUP_FULL` (not `402` — the joiner isn't the upsell target; the owner's plan governs capacity).

`maxGroupMembers` raised 50 → 200 (product-owner decision, 2026-07-22 — convention-scale groups, 000 §D15). Backend cost is flat (ingest fan-out is per-reporter and bounded by `maxActiveGroups`, not member count; the group map read stays one partition scan); the client-side consequence — map pin clustering above ~50 members — is deferred (000 §O17).

## 5. Non-goals & deferred (explicit)

- **Group location history / trails** — privacy: strangers-to-each-other would gain durable movement records; also a second history pipeline to guarantee-delete. Live-only is the feature.
- **Group geofences** — the geofence config is a family document; iOS's 20-region cap is already spoken for (000 §O9).
- **Group push-to-locate** — waking an acquaintance's device on demand crosses the trust line families have and groups don't; also quota entanglement.
- **Group push notifications** (member joined / ending soon) — deferred; type names reserved in 001 §8.7 (000 §O14). The sweeper's daily run is the natural future emitter for "ending soon".
- **Per-group pause** — 000 §O13; v1 answer is *leave*.
- **Ownership transfer** — 000 §O15; v1 answer: the owner ends or deletes the group (`ownerCannotLeave`, 001 §12.8).
- **HTTPS universal join links** — *promoted out of non-goals (2026-07-22):* spec'd in [007](007-public-join-links.md) (`https://{JOIN_LINK_HOST}/g#CODE`, static landing page, App Links / Universal Links, on-device QR). The in-app `findly://group-join?code=…` deep link remains valid. Still deferred to the future web spec: the web map/viz app itself.

## 6. Error cases

All codes from the 001 §10 catalog (no code invented here): `PROFILE_NOT_FOUND`, `GROUP_NOT_FOUND` (also masks non-membership), `GROUP_EXPIRED`, `GROUP_CODE_INVALID`, `GROUP_ALREADY_MEMBER`, `GROUP_FULL`, plus `LIMIT_EXCEEDED` (`maxActiveGroups` | `maxGroupDurationDays`), `VALIDATION_FAILED` (`details.reason: "ownerCannotLeave"`), and `MEMBER_NOT_FOUND` (kick target not in the group). Exact per-endpoint mapping in 001 §12.

## 7. Test checklist (conforming implementations)

- **Lifecycle × policy matrix:** every cell of §2.3 for all three policies — list filtering, `410` vs `404`, grace roster hiding (owner vs member), archive roster persistence, reactivation flipping `ended → active`, `PATCH endsAt` rejected on `archived`/expired.
- **Derived state:** `state()` pure-function edges — exactly `endsAt`, exactly `graceUntil`, policy variations (mutation testing must kill boundary mutants).
- **Sweeper:** finds expired groups only via the `GroupExpiry` index; re-buckets stale rows after owner extension; per-policy deletion sets (delete vs grace-at-endsAt vs grace-at-graceUntil vs archive); idempotent re-run after simulated crash mid-delete; expiry row deleted last; orphaned expiry rows cleaned.
- **Fan-out privacy:** `GroupLastKnown` rows never contain `deviceId`/`batteryPct`/`source`/altitude/speed/bearing; fan-out targets only `active` groups; paused device fans out nowhere; only-newer upsert per group; write count bounded by `maxActiveGroups`.
- **History gate:** a family-less reporter's accepted batch appends **no** history blob line; a family reporter's group membership adds none beyond the family append.
- **Bootstrap paths:** group create/join with no profile creates one (`displayName` required then); `PROFILE_NOT_FOUND` on everything else; family-less caller on family-scoped endpoints → `FAMILY_NOT_FOUND`.
- **Capacity & quotas:** `maxActiveGroups` counts owned + joined, excludes expired; `GROUP_FULL` at the **owner's** plan cap with `details.max`; duration horizon on create and patch.
- **Codes:** join by rotated code → `GROUP_CODE_INVALID`; double join → `GROUP_ALREADY_MEMBER`; rotate is owner-only; kick removes the member's location row immediately; owner leave → `VALIDATION_FAILED`/`ownerCannotLeave`.
- **Masking:** every `{groupId}` route answers `404 GROUP_NOT_FOUND` to non-members, indistinguishably from a nonexistent group.

## Open questions

None — deferred product matters are tracked in 000 §Open Items (O13 per-group pause, O14 group push, O15 ownership transfer) with v1 behavior fixed by this spec; O16 universal links was promoted to [007](007-public-join-links.md) (2026-07-22).
