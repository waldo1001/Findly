// specs/001 §13.2 `DELETE /api/v1/users/me` — account deletion (008 §4). Pure domain logic:
// no Azure/Google imports. Available to EVERY authenticated caller, including one with no
// profile at all (idempotent no-op, 001 §1.5.3 / 008 §4.1) — every step below is
// independently idempotent, so a caller with nothing left simply falls through every step as
// a no-op until step 8's (also idempotent) deleteProfile returns. Reuses B19's
// src/domain/family/familyDeletion.ts for the last-parent/sole-member cascade (008 §4.2) and
// src/domain/group/groupDeletion.ts for owned-group hard delete (001 §12.5) instead of
// reimplementing either teardown.
//
// Ordering is normative (002 §4.2) — devices FIRST (halts the subject's ingest immediately:
// their device-originated calls now fail DEVICE_NOT_FOUND), the Users profile row LAST (the
// completion marker AND the retry pointer: its familyId/role and residual group: rows are how
// a re-call finds whatever work is still outstanding):
//   1. Devices partition — deviceIds are collected here, BEFORE deletion, for step 3 (on
//      retry the partition is already empty, so there is nothing left to collect — the
//      documented "skip" case, 002 §4.2).
//   2. LastKnown partition.
//   3. IdempotencyMarkers — one partition per deviceId collected in step 1.
//   4. If in a family: LocateRequests rows naming the subject (requestedBy OR targetUserId).
//   5. Groups: owned -> full hard delete (§12.5 semantics); joined -> leave semantics
//      (§12.8 semantics). Runs regardless of family membership (groups are family-independent).
//   6. Usage — the subject's OWN uid-keyed partition. NOT conditional on family membership:
//      any period spent family-less (or between families, or groups-only) accumulated rows
//      under this uid (001 §9), so a CURRENT family member can still hold them from before
//      they joined. Family-keyed rows are household aggregates and are never touched here —
//      those go only with family deletion.
//   7. If in a family and NOT cascading: history/{familyId}/{uid}/ prefix delete, then the
//      events filtered rewrite, then the caller's own Families member row.
//   8. If cascading (008 §4.2 — see the cascade condition below): the shared family-deletion
//      footprint runs INSTEAD of step 7 — the whole-prefix wipe subsumes the events rewrite.
//   9. Users profile row — always, last, regardless of whether the caller was ever in a
//      family at all.
//
// Cascade condition (008 §4.2, narrowed after a security-review finding): cascade IFF the
// caller IS a parent and no OTHER parent remains, OR the caller is the SOLE member. The
// caller's own role is deliberately part of the condition — "no parent would remain" alone is
// NOT sufficient: the `Families` roster has no ETag guard (000 §O19), so two parents calling
// this concurrently can each observe the other and both take the non-cascade branch, leaving
// the family with zero parents. A remaining CHILD must NOT then be able to cascade merely
// because no parent is left — that would let a non-admin unilaterally erase every other
// member's data. The narrowed condition contains the blast radius of that race (a lingering
// parent-less family is recoverable; a child-triggered cascade is not) without closing the
// race itself, which is tracked separately (000 §O19).

import type {
  DeviceRepo,
  GroupCodeRepo,
  GroupExpiryRepo,
  GroupLastKnownRepo,
  GroupRepo,
  IdempotencyRepo,
  LastKnownRepo,
  LocateRequestRepo,
  Role,
  UsageRepo,
  UserRepo,
} from "../../ports/repositories";
import { deleteFamilyFootprint, type DeleteFamilyFootprintDeps } from "../family/familyDeletion";
import { hardDeleteGroupFootprint } from "../group/groupDeletion";

export interface DeleteAccountDeps extends DeleteFamilyFootprintDeps {
  deviceRepo: DeviceRepo;
  lastKnownRepo: LastKnownRepo;
  idempotencyRepo: IdempotencyRepo;
  groupRepo: GroupRepo;
  groupCodeRepo: GroupCodeRepo;
  groupLastKnownRepo: GroupLastKnownRepo;
  groupExpiryRepo: GroupExpiryRepo;
  userRepo: UserRepo;
  locateRequestRepo: LocateRequestRepo;
  usageRepo: UsageRepo;
}

export interface DeleteAccountInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5) — null for a family-less
   * profile AND for a caller with no profile at all (008 §4.1's bootstrap allowance): both
   * cases are handled identically here, since every step is a no-op with nothing to erase. */
  familyId: string | null;
  /** The caller's OWN role from the resolved auth context (§1.5), null for a family-less
   * profile or no profile at all. Part of the cascade condition (008 §4.2) — a non-parent
   * MUST NOT cascade even when the family already has no parent (000 §O19's race). */
  role: Role | null;
}

function bucketDateOf(isoTimestamp: string): string {
  return isoTimestamp.slice(0, 10);
}

/** Bare 204 (specs/001 §13.2) — no response body, so no `features` to return. */
export async function deleteAccount(input: DeleteAccountInput, deps: DeleteAccountDeps): Promise<void> {
  const { uid } = input;

  // Step 1: Devices partition — collect deviceIds BEFORE deleting (step 3 needs this
  // snapshot; a retry finds the partition already empty and correctly skips step 3).
  const deviceIds = (await deps.deviceRepo.listDevices(uid)).map((d) => d.deviceId);
  await deps.deviceRepo.deleteDevicesByOwner(uid);

  // Step 2: LastKnown partition.
  await deps.lastKnownRepo.deleteByOwner(uid);

  // Step 3: IdempotencyMarkers, one partition per deviceId collected in step 1.
  for (const deviceId of deviceIds) {
    await deps.idempotencyRepo.deletePartition(deviceId);
  }

  // Step 4: LocateRequests naming the subject — family-scoped only (no family, no partition).
  if (input.familyId) {
    await deps.locateRequestRepo.deleteRowsForUser(input.familyId, uid);
  }

  // Step 5: Groups — owned groups hard-deleted (§12.5 semantics), joined groups left
  // (§12.8 semantics). Family-independent: runs for family-less callers too.
  const memberships = await deps.userRepo.listGroupMemberships(uid);
  for (const membership of memberships) {
    if (membership.role === "owner") {
      const meta = await deps.groupRepo.getGroupMeta(membership.groupId);
      if (!meta) {
        // Orphaned reverse-index row (meta already gone — e.g. the sweeper or a previous
        // partial run already finished the job) — self-heal, same pattern as
        // listGroups.ts/exportUserData.ts.
        await deps.userRepo.removeGroupMembership(uid, membership.groupId);
        continue;
      }
      await hardDeleteGroupFootprint(meta, deps);
      await deps.groupExpiryRepo.deleteExpiryRow(bucketDateOf(meta.endsAt), membership.groupId);
    } else {
      await deps.groupRepo.removeMember(membership.groupId, uid);
      await deps.userRepo.removeGroupMembership(uid, membership.groupId);
      await deps.groupLastKnownRepo.removeMember(membership.groupId, uid);
    }
  }

  // Step 6: the subject's own uid-keyed Usage partition — unconditional on family membership
  // (a current family member can still hold uid-keyed rows from an earlier family-less
  // period). Family-keyed rows are never touched here; those go only with family deletion.
  await deps.usageRepo.deletePartition(uid);

  // Steps 7/8: family-scoped erasure, only when the caller is (still) in a family.
  if (input.familyId) {
    const familyId = input.familyId;
    const members = await deps.familyRepo.listMembers(familyId);
    const otherMembers = members.filter((m) => m.userId !== uid);
    const isSoleMember = otherMembers.length === 0;
    const isCallerParent = input.role === "parent";
    const otherParentRemains = otherMembers.some((m) => m.role === "parent");
    const cascade = (isCallerParent && !otherParentRemains) || isSoleMember;

    if (cascade) {
      // Cascade (008 §4.2, narrowed condition above) — the whole-family wipe subsumes the
      // events rewrite.
      await deleteFamilyFootprint(familyId, uid, deps);
    } else {
      await deps.historyStore.deleteUserPrefix(familyId, uid);
      await deps.historyStore.eraseUserFromEvents(familyId, uid);
      await deps.familyRepo.removeMember(familyId, uid);
    }
  }

  // Step 9: Users profile row LAST — the completion marker and retry pointer.
  await deps.userRepo.deleteProfile(uid);
}
