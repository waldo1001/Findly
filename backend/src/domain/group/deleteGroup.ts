// specs/001 §12.5 — delete group (owner). Bare 204 (no response body, no `features`).
// Immediate, synchronous hard delete of everything (members, code, locations, indexes —
// 005 §2.4), "in any state, regardless of policy" (001 §12.5, 005 §2.4, 002 §4.1 step 3) —
// deliberately NOT gated by derived state (unlike leave/kick, which reject `expired`, 001
// §12.8/§12.9): this is the same terminal action the sweeper would perform anyway, just
// synchronous. Pure domain logic: no Azure/Google imports. GroupLastKnown's partition wipe
// (002 §2.12/§4.1 step 3) is a single self-contained delete — no per-member fan-out needed,
// unlike the reverse-index rows below.

import { AppError } from "../../http/errors";
import type {
  GroupCodeRepo,
  GroupExpiryRepo,
  GroupLastKnownRepo,
  GroupRepo,
  UserRepo,
} from "../../ports/repositories";
import { hardDeleteGroupFootprint } from "./groupDeletion";

export interface DeleteGroupDeps {
  groupRepo: GroupRepo;
  groupCodeRepo: GroupCodeRepo;
  groupExpiryRepo: GroupExpiryRepo;
  groupLastKnownRepo: GroupLastKnownRepo;
  userRepo: UserRepo;
}

export interface DeleteGroupInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if family-less. */
  familyId: string | null;
  groupId: string;
}

function bucketDateOf(isoTimestamp: string): string {
  return isoTimestamp.slice(0, 10);
}

export async function deleteGroup(input: DeleteGroupInput, deps: DeleteGroupDeps): Promise<void> {
  const meta = await deps.groupRepo.getGroupMeta(input.groupId);
  if (!meta) {
    throw new AppError("GROUP_NOT_FOUND", "group not found");
  }

  const membership = await deps.groupRepo.getMember(input.groupId, input.uid);
  if (!membership) {
    // Masked: a non-member sees the same error as a nonexistent group (001 §12).
    throw new AppError("GROUP_NOT_FOUND", "group not found");
  }
  if (membership.role !== "owner") {
    throw new AppError("AUTH_FORBIDDEN", "only the group owner may delete the group");
  }

  // Same teardown the sweeper performs (002 §4.1 step 3, shared via groupDeletion.ts):
  // reverse-index rows -> GroupLastKnown partition -> code -> members -> meta, then the
  // expiry row LAST (own concern here since only this caller knows which bucket to target).
  await hardDeleteGroupFootprint(meta, deps);
  if (meta.endsAt !== null) {
    // A group without an end date has no GroupExpiry row at all (002 §2.13, 005 §2.5).
    await deps.groupExpiryRepo.deleteExpiryRow(bucketDateOf(meta.endsAt), input.groupId);
  }
}
