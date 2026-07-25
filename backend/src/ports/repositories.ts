// Repository ports the domain depends on. Interfaces only — real implementations live in
// src/adapters/tables/*; test/fakes/* provides in-memory versions for unit tests.
// Shapes follow specs/002-storage-schema.md tables 1:1; wire shapes are specs/001's problem, not these.

import type { SubscriptionStatus } from "../domain/plan";

export type Role = "parent" | "member";

// ---------------------------------------------------------------------------
// Families (specs/002 §2.1) — specs/001 §3.1 (this task), §3.2/3.5/3.6 (later tasks)
// ---------------------------------------------------------------------------

export interface FamilyMeta {
  familyId: string;
  familyName: string;
  createdBy: string;
  createdAt: string;
}

export interface FamilyMember {
  userId: string;
  role: Role;
  displayName: string;
  joinedAt: string;
}

// specs/002 §2.1 — the `invite:{code}` reverse-index row: written by invite creation (001
// §3.3) *after* the canonical §2.3 Invites row, read only by family deletion (002 §4.2) to
// find and revoke outstanding codes. The acceptance path never reads it (B19, specs/008 §5.3).
export interface FamilyInviteIndexEntry {
  code: string;
  expiresAt: string;
}

export interface FamilyRepo {
  /** Conditional insert of the `meta` row (001 §3.1). */
  createFamily(meta: FamilyMeta): Promise<void>;
  /** Point read of the `meta` row (001 §3.2). */
  getFamilyMeta(familyId: string): Promise<FamilyMeta | null>;
  /** Writes one `member:{userId}` row (001 §3.1 creator, §3.4 invite accept). */
  addMember(familyId: string, member: FamilyMember): Promise<void>;
  /** Partition range scan of `member:` rows = the roster (001 §3.2). */
  listMembers(familyId: string): Promise<FamilyMember[]>;
  /** Guarded update of a single member row (001 §3.5). */
  updateMember(
    familyId: string,
    userId: string,
    patch: Partial<Pick<FamilyMember, "role" | "displayName">>,
  ): Promise<FamilyMember>;
  /** Removes a member row (001 §3.6, 002 §4.2 step 2). Idempotent: swallows not-found so
   * family deletion's re-call converges (B19). */
  removeMember(familyId: string, userId: string): Promise<void>;
  /** Writes one `invite:{code}` index row (001 §3.3 side effect, 002 §2.1), after the
   * canonical Invites row. */
  addInviteIndexEntry(familyId: string, entry: FamilyInviteIndexEntry): Promise<void>;
  /** Partition range scan of `invite:` rows — family deletion's invite-revocation lookup
   * (002 §2.1/§4.2 step 2, B19). */
  listInviteIndexEntries(familyId: string): Promise<FamilyInviteIndexEntry[]>;
  /** Deletes one `invite:{code}` index row (002 §4.2 step 2, B19). Idempotent. */
  removeInviteIndexEntry(familyId: string, code: string): Promise<void>;
  /** Deletes the `meta` row — family deletion (001 §13.3, 002 §4.2 step 5, B19). Idempotent. */
  deleteFamilyMeta(familyId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Users — the auth hot path (specs/002 §2.2, specs/001 §1.5)
// ---------------------------------------------------------------------------

export interface UserProfile {
  /** Nullable — family-less users (groups only, 001 §1.5, 002 §2.2). */
  familyId: string | null;
  /** Denormalized from Families; null iff familyId is null (002 §2.2). */
  role: Role | null;
  displayName: string;
}

// specs/002 §2.2 — the `group:{groupId}` reverse-index row: "my groups" without a
// cross-partition query. Deliberately does NOT denormalize name/endsAt (see 002 §2.2).
export type GroupRole = "owner" | "member";

export interface GroupMembershipIndexEntry {
  groupId: string;
  role: GroupRole;
  joinedAt: string;
}

export interface UserRepo {
  /** The one point read every authenticated request performs (001 §1.5). */
  getProfile(userId: string): Promise<UserProfile | null>;
  /** Written alongside FamilyRepo.addMember in the same logical operation (001 §3.1, §3.4). */
  createProfile(userId: string, profile: UserProfile): Promise<void>;
  /** Role/displayName changes (001 §3.5) — Families stays the source of truth, this is a
   * cache. NOT idempotent: a missing profile row is a genuine bug for this caller
   * (updateMember.ts always operates on an already-validated roster member) and MUST
   * surface, not be swallowed — see clearFamilyMembership below for the one call site that
   * needs different semantics. */
  updateProfile(userId: string, patch: Partial<UserProfile>): Promise<void>;
  /** Membership removal (001 §3.6). */
  deleteProfile(userId: string): Promise<void>;
  /** Flips familyId/role to null — family deletion (001 §13.3, 002 §4.2 steps 1/6) and
   * B18's account-deletion cascade reuse this. Idempotent: swallows not-found, because a
   * concurrent DELETE /families/me/members/{userId} (001 §3.6) may have already deleted the
   * profile row entirely out from under a family deletion's own roster snapshot — every
   * other step of the 002 §4.2 sequence already tolerates this, this method closes the one
   * gap. Deliberately a DEDICATED method rather than making updateProfile itself swallow
   * not-found universally, which would mask genuine bugs in updateMember.ts's flow. */
  clearFamilyMembership(userId: string): Promise<void>;
  /** Writes one `group:{groupId}` reverse-index row (001 §12.1/§12.6, 002 §2.2). */
  addGroupMembership(userId: string, entry: GroupMembershipIndexEntry): Promise<void>;
  /** Partition scan of `group:` rows = the "my groups" reverse index (001 §12.2, 002 §2.2). */
  listGroupMemberships(userId: string): Promise<GroupMembershipIndexEntry[]>;
  /** Deletes one `group:{groupId}` reverse-index row — leave/kick/owner hard-delete
   * (001 §12.5/§12.8/§12.9, B10). Idempotent: a caller may retry after a partial failure. */
  removeGroupMembership(userId: string, groupId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Invites (specs/002 §2.3, specs/001 §3.3/§3.4) — later task (B3)
// ---------------------------------------------------------------------------

export interface InviteRecord {
  inviteCode: string;
  familyId: string;
  role: Role;
  emailHint?: string;
  createdBy: string;
  createdAt: string;
  expiresAt: string;
  usedBy?: string;
  usedAt?: string;
}

export type ConsumeInviteResult = "ok" | "alreadyUsed";

export interface InviteRepo {
  createInvite(invite: InviteRecord): Promise<void>;
  getInvite(inviteCode: string): Promise<InviteRecord | null>;
  /** ETag-guarded merge setting usedBy/usedAt; race-safe (001 §3.4, 002 §2.3). */
  consumeInvite(inviteCode: string, usedBy: string, usedAt: string): Promise<ConsumeInviteResult>;
  /** Deletes the canonical `{inviteCode}` row — family deletion's invite revocation, found
   * via the 002 §2.1 index rows (002 §4.2 step 2, B19). Idempotent. */
  deleteInvite(inviteCode: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Devices (specs/002 §2.4, specs/001 §4.1) — re-keyed to PK=ownerUserId (B8, specs/002 §2.4).
// Devices belong to users, not families: every method's partition-key argument is the
// device's OWNER's own userId — never a familyId. Family-wide reads (001 §4.2 listing,
// §5.2 live map, §6.1 locate-flow target resolution, §8.2/§8.4 push fan-out) are a
// `Families` roster scan plus one small per-member partition scan each, issued in
// parallel (src/domain/family/deviceFanout.ts) — never a single shared partition.
// ---------------------------------------------------------------------------

export type DevicePlatform = "android" | "ios";

export interface DeviceRecord {
  deviceId: string;
  ownerUserId: string;
  platform: DevicePlatform;
  model: string;
  appVersion: string;
  deviceName: string;
  pushToken?: string;
  locationPushToken?: string;
  pushInvalid: boolean;
  syncIntervalMinutes: number;
  trackingEnabled: boolean;
  registeredAt: string;
  lastSeenAt: string;
}

export interface DeviceRepo {
  getDevice(ownerUserId: string, deviceId: string): Promise<DeviceRecord | null>;
  /** Full upsert write — the domain computes the final merged state (001 §4.1). */
  putDevice(ownerUserId: string, device: DeviceRecord): Promise<void>;
  /** Partition scan = one owner's devices (001 §4.1 cap, §4.2/§5.2/§6.1/§8 fan-out inputs). */
  listDevices(ownerUserId: string): Promise<DeviceRecord[]>;
  /** Partition scan count = the per-user device-cap check (001 §4.1). */
  countDevices(ownerUserId: string): Promise<number>;
  /** Removes every device registration in the owner's partition (001 §3.6). */
  deleteDevicesByOwner(ownerUserId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// LastKnown (specs/002 §2.5, specs/001 §5.2) — re-keyed to PK=ownerUserId (B8), same
// owner-partition rule as Devices above.
// ---------------------------------------------------------------------------

export type FixSource = "periodic" | "locate" | "geofence" | "manual";

export interface LastKnownRecord {
  deviceId: string;
  lat: number;
  lon: number;
  accuracyM: number;
  altitudeM?: number;
  speedMps?: number;
  bearingDeg?: number;
  batteryPct: number;
  recordedAt: string;
  receivedAt: string;
  source: FixSource;
}

export interface LastKnownRepo {
  get(ownerUserId: string, deviceId: string): Promise<LastKnownRecord | null>;
  /** Overwrite only if incoming recordedAt > stored recordedAt; returns whether it wrote (002 §2.5). */
  upsertIfNewer(ownerUserId: string, record: LastKnownRecord): Promise<boolean>;
  /** One owner's partition scan (001 §5.2 fan-out input). */
  listByOwner(ownerUserId: string): Promise<LastKnownRecord[]>;
}

// ---------------------------------------------------------------------------
// Entitlements (specs/002 §2.6, specs/001 §3.1 — this task, §9)
// ---------------------------------------------------------------------------

export interface EntitlementsRecord {
  subscriptionStatus: SubscriptionStatus;
  updatedAt: string;
}

export interface EntitlementsRepo {
  /** Created at family creation with "free" (001 §3.1). */
  create(familyId: string, subscriptionStatus: SubscriptionStatus, updatedAt: string): Promise<void>;
  get(familyId: string): Promise<EntitlementsRecord | null>;
  /** Deletes the `entitlement` row — family deletion (002 §4.2 step 3, B19). Idempotent. */
  delete(familyId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// LocateRequests (specs/002 §2.7, specs/001 §6) — later task (B4)
// ---------------------------------------------------------------------------

export type LocateRequestStatus = "pending" | "fulfilled" | "expired" | "pushFailed";

export interface LocateRequestRecord {
  requestId: string;
  familyId: string;
  targetUserId: string;
  targetDeviceId: string;
  requestedBy: string;
  status: LocateRequestStatus;
  createdAt: string;
  expiresAt: string;
  fixJson?: string;
}

export interface LocateRequestRepo {
  create(record: LocateRequestRecord): Promise<void>;
  /** Point read on poll (001 §6.2). */
  get(familyId: string, requestId: string): Promise<LocateRequestRecord | null>;
  update(familyId: string, requestId: string, patch: Partial<LocateRequestRecord>): Promise<void>;
  /** Partition scan filtered to pending + same target = coalescing (001 §6.1). */
  listPendingByTargetDevice(familyId: string, targetDeviceId: string): Promise<LocateRequestRecord[]>;
  /** Wipes every `req:` row in the family's partition, regardless of status — family
   * deletion (002 §4.2 step 3, B19). Idempotent. */
  deletePartition(familyId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// IdempotencyMarkers (specs/002 §2.8, specs/001 §5.1/§7.3/§6.3) — later tasks (B2/B4)
// ---------------------------------------------------------------------------

export interface IdempotencyRepo {
  /** Conditional insert; false = already accepted (dedupe test, 001 §5.1). */
  tryInsertBatchMarker(
    deviceId: string,
    batchId: string,
    meta: { receivedAt: string; fixCount: number },
  ): Promise<boolean>;
  tryInsertEventMarker(deviceId: string, eventId: string, receivedAt: string): Promise<boolean>;
  tryInsertFixMarker(deviceId: string, fixId: string, receivedAt: string): Promise<boolean>;
}

// ---------------------------------------------------------------------------
// Usage (specs/002 §2.9, specs/001 §9 — this task exercises "apiCalls")
// ---------------------------------------------------------------------------

export type UsageMetric = "locationBatches" | "fixes" | "locateRequests" | "geofenceEvents" | "apiCalls";

export interface UsageRepo {
  /** Read → +by → ETag-guarded merge, retry loop handled by the adapter (002 §2.9). */
  increment(familyId: string, metric: UsageMetric, date: string, by?: number): Promise<void>;
  get(familyId: string, metric: UsageMetric, date: string): Promise<number>;
  /** Wipes every `{date}:{metric}` row in the family's partition — family deletion (002 §4.2
   * step 3, B19). Idempotent. */
  deletePartition(familyId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Groups (specs/002 §2.10, specs/001 §12.1-§12.3/§12.6 — this task; §12.4-§12.9 later (B10))
// ---------------------------------------------------------------------------

export type GroupExpiryPolicy = "delete" | "grace" | "archive";

export interface GroupMeta {
  groupId: string;
  name: string;
  ownerUserId: string;
  createdAt: string;
  endsAt: string;
  expiryPolicy: GroupExpiryPolicy;
  /** Current join code, denormalized for display (002 §2.10) — NOT the source of truth for
   * validity; that's GroupCodeRepo/GroupCodes (002 §2.11). */
  code: string;
  /** Optimistic-concurrency token for the `meta` row (Table Storage ETag) — populated by a
   * fresh `getGroupMeta` read so a caller that acts on that snapshot later (the sweeper, B12,
   * 002 §4.1) can detect a concurrent mutation (e.g. an owner's `PATCH endsAt`) via
   * `assertGroupMetaUnchanged` before doing anything destructive. Optional: absent wherever a
   * `GroupMeta` is constructed as a WRITE input (create/patch results) rather than read fresh. */
  etag?: string;
}

export type GroupMetaAssertOutcome = "ok" | "conflict";

export interface GroupMember {
  userId: string;
  role: GroupRole;
  /** Per-group display name (005 §1) — chosen at create/join, not editable in v1. */
  displayName: string;
  joinedAt: string;
}

export interface GroupRepo {
  /** Conditional insert of the `meta` row (001 §12.1, 002 §2.10). */
  createGroupMeta(meta: GroupMeta): Promise<void>;
  /** Point read of the `meta` row (001 §12.2/§12.3/§12.6). */
  getGroupMeta(groupId: string): Promise<GroupMeta | null>;
  /** Conditional insert of one `member:{userId}` row — race-safe join (001 §12.1/§12.6, 002 §2.10). */
  addMember(groupId: string, member: GroupMember): Promise<void>;
  /** Partition scan of `member:` rows = the roster + memberCount (001 §12.2/§12.3/§12.6). */
  listMembers(groupId: string): Promise<GroupMember[]>;
  /** Point read of a single member row — membership + role check (001 §12.3/§12.6). */
  getMember(groupId: string, userId: string): Promise<GroupMember | null>;
  /** Guarded merge of `name`/`endsAt`/`code` (001 §12.4 patch, §12.7 rotate; 002 §2.10/§2.11) —
   * returns the updated meta. B10. */
  updateGroupMeta(groupId: string, patch: Partial<Pick<GroupMeta, "name" | "endsAt" | "code">>): Promise<GroupMeta>;
  /** Deletes the `meta` row — owner hard delete (001 §12.5, 002 §4.1 step 3). B10. Idempotent. */
  deleteGroupMeta(groupId: string): Promise<void>;
  /** Deletes one `member:{userId}` row — leave/kick/owner hard-delete (001 §12.5/§12.8/§12.9).
   * B10. Idempotent. */
  removeMember(groupId: string, userId: string): Promise<void>;
  /**
   * Security fix (B12, 002 §4.1 TOCTOU): a conditional no-op verification against the `meta`
   * row's ETag. Succeeds ("ok") only if the row's current ETag still matches `etag` (the token
   * a caller captured at their own earlier `getGroupMeta` read) — mutates nothing else. A
   * mismatch, OR the row no longer existing at all, means `meta` was mutated or deleted
   * concurrently since that read; both surface as `"conflict"`, never a thrown error, so the
   * sweeper can skip the row for this run instead of acting on a stale snapshot. Mirrors
   * `GeofenceConfigRepo.replace`'s outcome-union style (never throws on the precondition
   * failure a stale caller is specifically trying to detect).
   */
  assertGroupMetaUnchanged(groupId: string, etag: string): Promise<GroupMetaAssertOutcome>;
}

// ---------------------------------------------------------------------------
// GroupCodes (specs/002 §2.11, specs/001 §12.6 — this task; §12.7 rotate later (B10))
// ---------------------------------------------------------------------------

export interface GroupCodeRecord {
  groupId: string;
  createdAt: string;
}

export interface GroupCodeRepo {
  /** Conditional insert of the `{code}` row (001 §12.1, 002 §2.11). */
  createCode(code: string, record: GroupCodeRecord): Promise<void>;
  /** Point read — the join lookup (001 §12.6, 002 §2.11). */
  getCode(code: string): Promise<GroupCodeRecord | null>;
  /** Deletes the `{code}` row — rotate's old code (001 §12.7) or the owner hard delete
   * (001 §12.5, 002 §4.1 step 3). B10. Idempotent. */
  deleteCode(code: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// GroupExpiry (specs/002 §2.13 — the sweeper's index; this task only writes the initial
// row at create, B10 moves it on PATCH endsAt, B12 is the sweeper that reads it)
// ---------------------------------------------------------------------------

export type GroupExpiryAction = "expire" | "hardDelete";

export interface GroupExpiryRow {
  groupId: string;
  action: GroupExpiryAction;
}

export interface GroupExpiryRepo {
  /** Writes the `{bucketDate}:{groupId}` row (002 §2.13) — bucket is the UTC date
   * (`yyyy-MM-dd`) of the group's next lifecycle action. */
  putExpiryRow(bucketDate: string, groupId: string, action: GroupExpiryAction): Promise<void>;
  /** Deletes the `{bucketDate}:{groupId}` row — moved on `PATCH endsAt` (002 §2.13, B10) or
   * removed entirely by the owner hard delete (001 §12.5, 002 §4.1 step 3, last). Idempotent
   * by design: the row may already be at a different bucket (a prior partial move or a sweeper
   * pass) — callers MUST tolerate this as a harmless no-op (002 §2.13's self-healing note). */
  deleteExpiryRow(bucketDate: string, groupId: string): Promise<void>;
  /** Partition scan of one `{bucketDate}` bucket — the sweeper's bucket walk (002 §2.13/§4.1,
   * B12): "a handful of tiny date-partition scans — never a full table scan." */
  listByDate(bucketDate: string): Promise<GroupExpiryRow[]>;
}

// ---------------------------------------------------------------------------
// GroupLastKnown (specs/002 §2.12, specs/001 §5.1 fan-out side effect + §12.10 — this
// task, B11). One row per member per group — deliberately field-minimal (position-only,
// 005 §3): no deviceId, batteryPct, source, altitudeM, speedMps, bearingDeg. Same
// owner(group)-partition + only-newer idiom as LastKnown (002 §2.5).
// ---------------------------------------------------------------------------

export interface GroupLastKnownRecord {
  userId: string;
  lat: number;
  lon: number;
  accuracyM: number;
  recordedAt: string;
  receivedAt: string;
  /** Frozen at write time from the reporting device's settings — feeds isStale (001 §12.10). */
  syncIntervalMinutes: number;
}

export interface GroupLastKnownRepo {
  /** Overwrite only if incoming recordedAt > stored recordedAt (same only-newer idiom as
   * LastKnown §2.5); returns whether it wrote. */
  upsertIfNewer(groupId: string, record: GroupLastKnownRecord): Promise<boolean>;
  /** One groupId partition scan = the group map read (001 §12.10). */
  listByGroup(groupId: string): Promise<GroupLastKnownRecord[]>;
  /** Deletes one member's position row — leave/kick (001 §12.8/§12.9, B10): "their position
   * disappears from the group map immediately." Idempotent. */
  removeMember(groupId: string, userId: string): Promise<void>;
  /** Wipes the whole groupId partition — owner hard delete (001 §12.5, 002 §4.1 step 3, B10)
   * and the sweeper's per-policy location cleanup (002 §4.1 steps 3-5, B12). Idempotent. */
  deletePartition(groupId: string): Promise<void>;
}
