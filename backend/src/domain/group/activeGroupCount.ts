// specs/005 §4, 001 §9/§12.1/§12.4/§12.6 — the caller-scoped group caps count the caller's
// `active` groups only, split by the `Users` `group:` row's role: owned groups against
// `maxOwnedGroups`, joined ones against `maxJoinedGroups`. `ended` (grace), `archived` and
// `expired` groups never count. Pure domain logic: no Azure/Google imports.

import type { GroupRepo, GroupRole, UserRepo } from "../../ports/repositories";
import { deriveGroupState } from "./groupState";

export async function countActiveGroupsWithRole(
  uid: string,
  role: GroupRole,
  now: Date,
  groupGraceDays: number,
  deps: { userRepo: UserRepo; groupRepo: GroupRepo },
  excludeGroupId?: string,
): Promise<number> {
  const memberships = await deps.userRepo.listGroupMemberships(uid);
  let count = 0;
  for (const membership of memberships) {
    if (membership.role !== role) continue;
    if (membership.groupId === excludeGroupId) continue;
    const meta = await deps.groupRepo.getGroupMeta(membership.groupId);
    if (!meta) continue; // orphaned reverse-index row (self-healing skip)
    if (deriveGroupState(now, meta.endsAt, meta.expiryPolicy, groupGraceDays) === "active") count += 1;
  }
  return count;
}
