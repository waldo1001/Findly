// Shared physical-deletion mechanics for a family's whole footprint (specs/001 §13.3,
// specs/008 §5, specs/002 §4.2). Extracted so the parent-triggered synchronous delete
// (DELETE /families/me, deleteFamily.ts) and B18's last-parent/sole-member account-deletion
// cascade (specs/008 §4.2) perform the exact same teardown instead of two independent
// implementations drifting apart — mirrors src/domain/group/groupDeletion.ts's role for
// group hard-delete. Pure domain logic: no Azure/Google imports.
//
// Ordering is normative (002 §4.2) and is what makes a crash-anywhere retry converge:
//   1. Every OTHER member's Users profile flips family-less FIRST — the auth boundary
//      (001 §1.5): their ingest stops appending and their family reads 404 immediately.
//   2. Families member: + invite: rows deleted; each invite: index row's canonical
//      Invites row goes with it (revoking outstanding codes, specs/008 §5.3).
//   3. Entitlements, the Usage partition, the LocateRequests partition.
//   4. Blob prefixes: history/{familyId}/, events/{familyId}/, config/{familyId}/.
//   5. Families meta row.
//   6. The CALLER's own profile flips family-less LAST — until this runs they remain a
//      parent-with-familyId, which is what lets a crashed-out retry re-enter the endpoint's
//      role check (001 §1.6) and resume by familyId value; every step above is independently
//      idempotent (swallows not-found) so re-running any prefix of them is always safe.
//
// Deliberately does NOT depend on DeviceRepo/LastKnownRepo/group-membership mutation:
// members' accounts survive family-less (specs/008 §5.2) — devices, last-known, and group
// memberships are all keyed per-user and must never be touched here. Leaving them out of
// this function's dependency list makes that a compile-time property, not just a promise.

import type {
  EntitlementsRepo,
  FamilyRepo,
  InviteRepo,
  LocateRequestRepo,
  UsageRepo,
  UserRepo,
} from "../../ports/repositories";
import type { GeofenceConfigRepo } from "../../ports/geofenceConfig";
import type { HistoryStore } from "../../ports/historyStore";

export interface DeleteFamilyFootprintDeps {
  familyRepo: FamilyRepo;
  userRepo: UserRepo;
  inviteRepo: InviteRepo;
  entitlementsRepo: EntitlementsRepo;
  usageRepo: UsageRepo;
  locateRequestRepo: LocateRequestRepo;
  historyStore: HistoryStore;
  geofenceConfigRepo: GeofenceConfigRepo;
}

/**
 * Tears down every family-scoped row/blob for `familyId` (specs/008 §2 "Family delete"
 * column), in the normative 002 §4.2 order. `callerUid` is excluded from the step-1 fan-out
 * and flipped separately, last, in step 6. Safe to call repeatedly — every underlying
 * repo/store method it calls is documented idempotent (swallows not-found), and this
 * function reads live state (listMembers/listInviteIndexEntries) on every call rather than
 * trusting a snapshot, so it always resumes from wherever a prior crash left off.
 */
export async function deleteFamilyFootprint(
  familyId: string,
  callerUid: string,
  deps: DeleteFamilyFootprintDeps,
): Promise<void> {
  // Step 1: every OTHER member's profile flips family-less first (the auth boundary).
  const members = await deps.familyRepo.listMembers(familyId);
  for (const member of members) {
    if (member.userId === callerUid) continue;
    await deps.userRepo.updateProfile(member.userId, { familyId: null, role: null });
  }

  // Step 2: Families member: + invite: rows; each invite: index row's canonical Invites
  // row is revoked with it (specs/008 §5.3). The caller's own member: row is wiped here
  // too — it stops being the roster's problem the moment step 1 finished; the caller keeps
  // access via their Users profile (untouched until step 6), not via this roster row.
  const inviteIndexEntries = await deps.familyRepo.listInviteIndexEntries(familyId);
  for (const entry of inviteIndexEntries) {
    await deps.inviteRepo.deleteInvite(entry.code);
    await deps.familyRepo.removeInviteIndexEntry(familyId, entry.code);
  }
  for (const member of members) {
    await deps.familyRepo.removeMember(familyId, member.userId);
  }

  // Step 3: Entitlements, Usage partition, LocateRequests partition.
  await deps.entitlementsRepo.delete(familyId);
  await deps.usageRepo.deletePartition(familyId);
  await deps.locateRequestRepo.deletePartition(familyId);

  // Step 4: blob prefixes — history/events (both containers) then the geofence config.
  await deps.historyStore.deleteFamilyPrefix(familyId);
  await deps.geofenceConfigRepo.deleteConfig(familyId);

  // Step 5: the Families meta row.
  await deps.familyRepo.deleteFamilyMeta(familyId);

  // Step 6: the caller's own profile flip, LAST — the retry pointer.
  await deps.userRepo.updateProfile(callerUid, { familyId: null, role: null });
}
