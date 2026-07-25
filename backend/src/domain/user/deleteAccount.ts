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
//   6. If in a family and NOT cascading: history/{familyId}/{uid}/ prefix delete, then the
//      events filtered rewrite, then the caller's own Families member row.
//   7. If cascading (last parent / sole member — 008 §4.2, "no parent-less zombie
//      families"): the shared family-deletion footprint runs INSTEAD of step 6 — the
//      whole-prefix wipe subsumes the events rewrite.
//   8. Users profile row — always, last, regardless of whether the caller was ever in a
//      family at all.

import type {
  DeviceRepo,
  GroupCodeRepo,
  GroupExpiryRepo,
  GroupLastKnownRepo,
  GroupRepo,
  IdempotencyRepo,
  LastKnownRepo,
  LocateRequestRepo,
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
}

export interface DeleteAccountInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5) — null for a family-less
   * profile AND for a caller with no profile at all (008 §4.1's bootstrap allowance): both
   * cases are handled identically here, since every step is a no-op with nothing to erase. */
  familyId: string | null;
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

  // Steps 6/7: family-scoped erasure, only when the caller is (still) in a family.
  if (input.familyId) {
    const familyId = input.familyId;
    const members = await deps.familyRepo.listMembers(familyId);
    const familyHasOtherParent = members.some((m) => m.userId !== uid && m.role === "parent");

    if (!familyHasOtherParent) {
      // Cascade (008 §4.2): the caller is the last parent, or the sole member — no
      // parent-less zombie families. The whole-family wipe subsumes the events rewrite.
      await deleteFamilyFootprint(familyId, uid, deps);
    } else {
      await deps.historyStore.deleteUserPrefix(familyId, uid);
      await deps.historyStore.eraseUserFromEvents(familyId, uid);
      await deps.familyRepo.removeMember(familyId, uid);
    }
  }

  // Step 8: Users profile row LAST — the completion marker and retry pointer.
  await deps.userRepo.deleteProfile(uid);
}
