# 008 — Privacy: data export & deletion

## Goal

The privacy surface required before any store release (000 §O7): **per-member data export** (GDPR Art. 15/20 — children's location data, EU users), **account deletion** (Google Play account-deletion policy; Apple guideline 5.1.1(v); GDPR Art. 17), and **family deletion** — plus the Play-required **web deletion page**. This spec owns the concepts, semantics, and guarantees; wire shapes live only in [001 §13](001-api-contract.md), storage coverage/ordering only in [002 §4.2](002-storage-schema.md).

RFC 2119 keywords (MUST/SHOULD/MAY) are used normatively.

Product decisions locked in (2026-07-25): web deletion is **self-service** (not request-by-email); deletion is **immediate hard delete** (no recovery window); a last-parent account deletion **cascades to family deletion**.

## 1. Concepts

### 1.1 Removal vs erasure (normative distinction)

- **Removal** (existing §3.6): a parent removes a member — membership and devices go, historical data stays under normal retention (000 §Roles). Administrative, reversible by re-invite.
- **Erasure** (this spec): the account holder deletes their **account** — everything about them is physically deleted, including their location history and their lines in the family's geofence-event history. Erasure is strictly stronger than removal and is never performed on someone else's behalf in v1 (§7).

### 1.2 Immediate deletion (no recovery window)

Both deletion endpoints execute **synchronously and irreversibly** in the request — same ethos as group deletion (005 §2.4: "temporary must mean actually deleted"). There is no tombstone/pending state, no restore endpoint, and no sweeper involvement. Fat-finger protection is client UX: both clients MUST show a two-step confirmation that names the consequences (§4.4, §5.4), and the family-delete confirmation MUST state that up to the full retention window of family history is destroyed.

### 1.3 The Firebase side of an account

The backend holds no Google credential (000 §D9) and MUST NOT gain one for deletion. The Firebase Auth user record (which is where the phone number lives — 006 §2) is deleted **client-side** via the Firebase SDK (`user.delete()` / `currentUser.delete()`), **after** the backend confirms `DELETE /users/me`. Ordering rationale: an orphaned Firebase user with no Findly data is harmless (holds only the phone number); the reverse orphan — Findly data with no account — would be an erasure failure.

**Recovery when the Firebase step fails (normative).** `user.delete()` commonly fails with `requires-recent-login`, and by then the backend deletion has already succeeded irreversibly. A bare "retry" is therefore a **trap**: the session is not going to become recent on its own, so every retry fails identically and the user is stuck forever. Clients MUST instead offer **sign out → sign in again → re-run delete**, which works precisely because of two properties this spec already guarantees: `DELETE /users/me` is an **idempotent no-op for a profile-less caller** (§4.1), and the privacy UI is **reachable without a profile** (§4.4). After a fresh sign-in the session is recent, the backend call returns `204` having nothing left to do, and `user.delete()` succeeds. Clients MUST NOT require an in-place re-authentication sub-flow (for phone auth that means a second SMS round-trip for no benefit), and MUST make the sign-out action reachable from the failure state itself — an app with no sign-out entry point leaves the user with no path at all.

## 2. Data inventory (what each operation covers)

Erasure and export are defined against the complete 002 inventory. Per subject `uid`:

| Data | Where (002) | Export (§3) | Account delete (§4) | Family delete (§5) |
|---|---|---|---|---|
| Profile (`displayName`, `familyId`, `role`) | `Users` §2.2 | yes | deleted (last — completion marker) | `familyId`/`role` → null |
| Group memberships + reverse index | `Users`/`Groups` §2.2/§2.10 | yes (membership facts) | owned → §12.5 hard delete; joined → leave semantics | untouched |
| Devices | `Devices` §2.4 | yes (minus push tokens — write-only, 001 §4.1) | deleted | untouched (user-owned) |
| Last-known positions | `LastKnown` §2.5 | yes | deleted | untouched (user-owned) |
| Group positions | `GroupLastKnown` §2.12 | yes (own rows) | deleted via the per-group handling | untouched |
| Location history | `history/{familyId}/{uid}/…` §3.1 | yes — **full physical retention (400 d), not the `historyDays` read window** (Art. 15 covers everything held) | own prefix deleted | whole family prefix deleted |
| Geofence events | `events/{familyId}/…` §3.1 (interleaved) | yes — own lines filtered | **own lines rewritten out** (§4.3) | whole prefix deleted |
| Geofence config | `config/{familyId}/…` §3.1 | no (family document, not subject data; home/school coordinates are family-shared) | untouched (unless cascade) | deleted |
| Locate requests naming the subject | `LocateRequests` §2.7 (`fixJson` holds coordinates) | no (transient, ≤60 s lifecycle; coordinates also in history) | rows where `requestedBy` or `targetUserId` = uid deleted | partition deleted |
| Idempotency markers | `IdempotencyMarkers` §2.8 | no (opaque dedupe keys) | partitions of the subject's devices deleted | untouched (devices survive) |
| Usage counters | `Usage` §2.9 | uid-keyed rows only (family-keyed are household aggregates, not subject-scoped) | uid-keyed partition deleted | family partition deleted |
| Invites | `Invites` §2.3 + family index (002 §2.1) | no | untouched | canonical + index rows deleted; stragglers fail closed (001 §3.4) |
| Phone number + sign-in metadata | Firebase Auth (006 §2 — never in Findly storage) | referenced in the export's `providerData` note | client-side `user.delete()` (§1.3) | n/a |

## 3. Export

- **Who:** any user with a profile exports **themselves**; a **parent** may export any current member of their family (open-family precedent — parents already see all of it). A non-parent requesting another user → `403 AUTH_FORBIDDEN`; a parent naming a non-member → `404 MEMBER_NOT_FOUND`. Removed ex-members are not exportable targets (their retained history remains reachable via 001 §5.3 until retention expires).
- **What:** one self-contained JSON document (shape: 001 §13.1) covering every "yes" row of §2 — including location history to the **full physical retention window**, deliberately beyond `features.limits.historyDays`.
- **How:** **synchronous streaming download** — deliberately no export files at rest (a stored export would be a second PII copy to secure and clean up) and no async job state. The response is the document itself, unenveloped, with `Content-Disposition: attachment` (the documented envelope exception, 001 §1.3/§13.1). No pagination: size is bounded by retention at family scale (single-digit MB; 002 §5).
- **Quota:** `features.limits.exportsPerDay` (free: 3), counted against the **caller**, metric `exports` (002 §2.9) → `402 LIMIT_EXCEEDED`, `details.limit: "exportsPerDay"`. Export is the most expensive read in the system (~800 small blob reads worst case); the quota is the abuse bound.
- Clients (003 §12.4 / 004 §3.6) MUST offer export in settings and hand the file to the OS share/save sheet, subject to §3.1.

### 3.1 Export-artifact hygiene (normative — both platforms)

The export document is the most sensitive payload in the product: one subject's complete movement history to the full retention window, in plaintext, in a single file. A parent may export a **child**. Handing it to a share sheet requires materialising it, and a naive implementation leaves an un-erasable second copy of exactly the data §4/§5 exist to destroy — defeating the deletion guarantee from the outside. Therefore:

1. **App-private storage only.** Written inside the app sandbox — never external/shared storage, never a location another app can read without an explicit, temporary grant.
2. **Bounded lifetime — but never racing the consumer.** The OS share sheet hands a URI to *another* application, which may read it lazily and asynchronously; on Android the chooser's activity-result callback fires as soon as the target is launched, **not** when it has finished reading. Deleting on that signal therefore destroys the file underneath "Save to Files/Drive"-style targets and silently breaks the export. Clients MUST NOT delete the artifact on share-sheet dismissal, cancellation, or return. Instead it MUST be removed: (a) **immediately before writing a new export**, so at most one artifact ever exists; (b) on the **next app cold start**; and (c) by the **account-deletion local wipe** (§4.4). Screen teardown MAY also clear it *only* where the platform guarantees the consumer has already copied the data. This bounds the artifact to a single session and guarantees it never outlives the account, without racing the app the user deliberately shared to — privacy that breaks the feature is not privacy, it is a bug.
3. **No durable identifier in the filename.** The user-visible *suggested* name MAY be friendly, but the on-disk name MUST NOT embed a stable `userId`/`uid` that outlives the request — a directory listing must not become a roster of which family members have been exported.
4. **Platform data-protection explicitly set**, not inherited by default: iOS `.completeFileProtection` plus exclusion from backup; Android app-private storage with a **narrowly scoped** `FileProvider` path (never `<root-path>`) and only a temporary read grant on the share intent.
5. **No HTTP caching.** The server MUST send `Cache-Control: no-store` on the export response (001 §13.1) and clients MUST additionally defeat local caching on this request rather than relying on the header — otherwise the HTTP cache silently becomes a third on-disk copy outside the app's own file handling.
6. **Never build a path from a server-supplied filename.** The `Content-Disposition` filename is a *display* hint only. Clients MUST derive the on-disk name themselves, or sanitize the header value by rejecting any path separator (`/`, `\`) or `..` segment and falling back to a safe default. This is not theoretical: Java's `File(parent, child)` does **not** normalize `..`, so an unsanitized header value escapes the intended directory and can overwrite app-private files. The client treats the backend as untrusted input here — a compromised or simply buggy server must not be able to steer a write.

## 4. Account deletion — `DELETE /users/me`

### 4.1 Semantics

Available to **every** authenticated user, including one with **no profile** (idempotent no-op → `204` — this both covers the "signed in but never bootstrapped" state and makes crash-retry converge, §4.5). Erases every "account delete" row of §2, then the client performs the Firebase step (§1.3).

### 4.2 The family cascade (last parent / sole member)

Refusing erasure is not an option. The cascade condition is **exactly** this, and it is deliberately narrower than "no parent would remain":

> Cascade **iff** — the caller **is a parent** and no *other* parent remains, **or** the caller is the **sole member**.

The caller's own role is part of the condition, not an incidental detail. A **non-parent MUST NOT cascade**, even when the family already has no parent at all. Such a parent-less family is a defect (it should be unreachable — the last-parent guards of §3.5/§3.6 and this rule exist to prevent it), but the correct response to finding one is *not* to let a child unilaterally erase every other member's data. Deleting only their own account leaves a recoverable situation; cascading turns one member's private decision into irreversible family-wide destruction by someone who was never an admin. Where the two failure modes are "a broken family lingers" and "a child wipes the family", the first is strictly preferable.

**Concurrency caveat (known, tracked):** the roster read backing this decision is not atomic — two parents deleting simultaneously can each observe the other and both take the non-cascade branch, leaving the parent-less family described above. The narrow condition above contains the *blast radius* of that race; closing the race itself needs optimistic concurrency on the `Families` roster, which the same read-then-write pattern in §3.5/§3.6 already lacks and which is therefore tracked separately (000 §O19) rather than bolted onto this endpoint. Otherwise (co-parents remain, or the caller is a non-parent member) the family survives: the caller's member row is deleted, their history prefix and event lines are erased (stronger than §3.6 removal — §1.1), and the roster shrinks. Clients MUST present the cascade consequence explicitly in the confirmation when the caller is the last parent ("you are the only parent — this deletes the family for everyone"). Other members keep their accounts, devices, and groups, and land in the family-less state (001 §1.5.4).

### 4.3 Interleaved event-line erasure

`events/{familyId}/{date}.jsonl` blobs interleave all members (002 §3.1), so per-subject erasure is a **filtered rewrite**: read the day-blob, drop lines with the subject's `userId`, `If-Match`-guarded delete, recreate-and-append the filtered lines (002 §4.2 owns the exact sequence and its concurrency guard). Past-day blobs are immutable; only the current UTC day can race a concurrent append, and the guard makes that lossless. Skipped entirely when the family cascade (§4.2) wipes the whole prefix anyway.

### 4.4 Client obligations

Both clients MUST: gate the action behind a two-step confirmation naming the consequences (device data, history, groups; the cascade when applicable); call `DELETE /users/me`; on `204` call the Firebase SDK delete; on Firebase failure offer retry (§1.3); then clear all local state and return to sign-in. The settings entry MUST be reachable without contacting support (store requirement).

### 4.5 Idempotency & ordering

The operation is **re-callable until it returns `204` with nothing left**: every step swallows not-found, and the deletion order (normative in 002 §4.2) deletes the subject's **devices first** (halting their ingest immediately) and the **profile row last** (the completion marker — the pointer that lets a retry find everything else). A crash mid-way is resolved by calling again; clients SHOULD retry on 5xx/timeouts.

## 5. Family deletion — `DELETE /families/me`

### 5.1 Semantics

**Parent-only.** Synchronously and irreversibly deletes every "family delete" row of §2: the family's identity, roster, entitlements, usage, locate requests, invites (canonical + index), geofence config, and **all** history and event blobs — for every member, the full retention window. Returns `204`.

### 5.2 What survives

Members' **accounts survive**: profiles (now family-less), devices, last-known, and group memberships are untouched (all keyed per-user — 000 §D11 made this surgical). Their devices keep reporting; the history gate (001 §5.1) stops appending — for new requests via the profile flip, and for requests already in flight via the **write-time family-existence guard** (002 §4.2), without which an in-flight batch could permanently resurrect coordinates under the erased family. There is no push notification in v1 — members discover the change on their next family-scoped call (`404 FAMILY_NOT_FOUND`) and land on the family-less home both clients already implement (deferred: a courtesy push, 000 §O14 family).

### 5.3 Invite revocation

Outstanding invite codes are revoked as part of the delete, found via the family-side index rows (002 §2.1). Belt-and-braces: invite acceptance **fails closed** when the family no longer exists (001 §3.4 → `INVITE_INVALID`), so an index row missed by a partial failure can never resurrect a deleted family.

### 5.4 Client obligations

Parent-only settings entry; two-step confirmation that names the irreversible loss of the **whole family's** history for all members. Recommended UX: require typing the family name.

### 5.5 Idempotency & ordering

Re-callable until clean (002 §4.2): other members' profiles are flipped family-less **first** (the auth boundary — their ingest stops appending immediately), the **caller's own profile is flipped last** (they must stay a parent-with-`familyId` so a retry can re-enter and finish). A crash after meta deletion but before the caller's flip leaves the caller pointing at a gone family; the re-call proceeds by `familyId` value and swallows not-founds.

## 6. Web deletion page — `/delete-account`

Google Play requires a **web resource** where users can delete their account without reinstalling the app. Decision: **self-service** — the page performs the real deletion, so identity is verified by the SMS sign-in itself (a request-by-email flow can't honestly verify ownership of a phone-number account).

### 6.1 Page contract

Hosted on the join-link SWA (007's host), route `/delete-account`. Flow: explanation → Firebase JS SDK **phone sign-in** (same test-number support, reCAPTCHA verification on web) → a confirmation step naming the consequences (incl. the §4.2 cascade when the backend reports a family — the page MAY simply always show the strongest warning) → `DELETE /users/me` with the web-minted ID token → Firebase `user.delete()` → done state. Failure of the Firebase step shows the same retry guidance as §1.3.

Page rules: no analytics, no storage of any user data, nothing persisted beyond the Firebase SDK's own session handling; no capability in the URL (unlike `/g`, there is nothing secret in this page's address). The page MUST NOT be framable — see the site-wide requirement in [007 §5](007-public-join-links.md), which this page is the reason for: a clickjacked join flow is an annoyance, a clickjacked deletion flow is irreversible. The 007 join page's "zero external resources" rule is **explicitly not inherited** — this page MUST load the Firebase JS SDK; that rule exists for the join page's no-oracle/capability-URL properties, which don't apply here.

### 6.2 Infrastructure prerequisites (human/ops — tracked as H9)

1. **Firebase web app** registered in `findly-71f7b`; SWA host (and any later custom domain, 007 §6) added to Firebase Auth **authorized domains**.
2. **CORS on the Function App** allowing the SWA origin (methods `DELETE`+preflight, `Authorization` header) — the API's first browser caller.
3. **App Check**: before H8 flips enforcement ON for Authentication, the web app MUST be registered with the web App Check provider (reCAPTCHA), or this page's sign-in breaks — H8's checklist gains this item.
4. SMS region policy (006 §6.3) applies to the page exactly as to the apps.

## 7. Non-goals & deferred (explicit)

- **Parent-initiated per-member erasure** ("erase my kid's data but keep their account") — v1 answers: §3.6 removal (history retained under retention), family deletion, or account deletion run from the child's own device. Tracked as 000 §O18.
- **Recovery window / soft delete** — rejected for v1 (§1.2); revisit only with real-user evidence of accidental deletions.
- **Web export** — export is in-app + API only; Play doesn't require a web export surface.
- **Deletion audit dashboard** — standard request telemetry (`requestId`-correlated, PII-safe per B15) is the audit trail.
- **Backend-side Firebase user deletion** — permanently out (would require a Google admin credential, violating 000 §D9's credential-free auth).

## 8. Error cases

All codes from the 001 §10 catalog (nothing new invented): `AUTH_FORBIDDEN` (non-parent family delete / non-parent exporting another user), `MEMBER_NOT_FOUND` (parent exporting a non-member), `LIMIT_EXCEEDED` (`details.limit: "exportsPerDay"`), `VALIDATION_FAILED` (malformed `userId` param), `INVITE_INVALID` (fail-closed accept, §5.3), plus the standard auth set. `PROFILE_NOT_FOUND` applies to export but deliberately **not** to `DELETE /users/me` (§4.1). Exact per-endpoint mapping: 001 §13.

## 9. Test checklist (conforming implementations)

- **Export:** self-export for member and family-less caller; parent-for-member; forbidden/not-found matrix; document covers every §2 "yes" row; history included **beyond `historyDays`** to full retention; push tokens absent; family-keyed usage absent, uid-keyed present; quota `exportsPerDay` enforced from `PLAN_MATRIX` (mutation-killable); unenveloped body + attachment header.
- **Account delete:** full erasure of every §2 row (verify storage empty via fakes/Azurite) — **including the subject's uid-keyed `Usage` partition, which a *current family member* can still hold from any earlier family-less period** (002 §4.2 step 6), while family-keyed rows must survive; devices-first / profile-last ordering; re-call after simulated crash at every step boundary converges to `204`; no-profile caller → `204` no-op; owned groups hard-deleted, joined groups left; locate rows naming the subject gone; event-line rewrite removes only the subject's lines (other members' lines byte-identical) incl. the concurrent-append race (002 §6); cascade triggers on last-parent and sole-member, not on co-parent; non-cascade path leaves the family intact for others.
- **Family delete:** parent-only; every family-scoped row/blob gone; members flipped family-less (others first, caller last); member accounts/devices/groups untouched; outstanding invites revoked via index; §3.4 fail-closed accept on a deleted family; re-call idempotency.
- **Erasure against never-created storage (002 §4.2):** `DELETE /users/me` and `DELETE /families/me` MUST return `204` when the underlying tables/containers do not exist at all — the list step must tolerate `TableNotFound`/`ContainerNotFound`, not just the per-row delete. Must be tested against **real** storage with the table/container deliberately absent: in-memory fakes cannot model a missing table, and an integration suite that creates them in setup masks it. The no-profile no-op path (§4.1) is the one most likely to hit this, since it is reachable before anything has ever been written.
- **In-flight erasure race (002 §4.2 write-time guard):** a `POST /locations` whose auth context resolved *before* the deletion, and whose write lands *after* the blob wipe, MUST NOT recreate history or a family-keyed usage row — it degrades to the family-less path instead. The test must drive the deletion between the ingest path's family read and its write (not merely assert the guard exists), and confirm the batch still succeeds with last-known/group fan-out intact.
- **Web page (W2):** static checks in the spirit of W1 (no analytics/storage beyond Firebase SDK); flow states incl. Firebase-delete failure + retry; CORS preflight against the deployed Function App.
- **Clients:** two-step confirmations (cascade wording when last parent); Firebase `user.delete()` ordering after `204`; retry UX on Firebase failure; local-state wipe + return to sign-in; settings discoverability.
- **Export-artifact hygiene (§3.1):** the artifact is **not** deleted on share-sheet return/dismissal (that would race a lazily-reading consumer — verify no such trigger exists); it *is* cleared before a new export, on next cold start, and by the account-deletion wipe; a second export does not accumulate a second file; the on-disk name carries no durable `userId`; the account-deletion wipe removes any stray artifact; the file lives in app-private storage with data protection explicitly set (iOS `.completeFileProtection` + backup-excluded; Android narrow `FileProvider` path, never `<root-path>`, temporary grant only); the request defeats local HTTP caching and the response carries `Cache-Control: no-store`.

## Open questions

None — deferred matters are tracked in 000 §Open Items (O18 per-member erasure; O14 gains the family-deleted courtesy push) with v1 behavior fixed by this spec.
