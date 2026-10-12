// specs/001 §12.2 response shape (also the common prefix of §12.1/§12.3/§12.6). Pure domain
// logic: no Azure/Google imports.

import type { GroupExpiryPolicy, GroupMeta, GroupRole } from "../../ports/repositories";
import type { GroupState } from "./groupState";

export interface GroupListItem {
  groupId: string;
  name: string;
  /** null = no end date (005 §2.5, 001 §12.2). */
  endsAt: string | null;
  expiryPolicy: GroupExpiryPolicy;
  state: Exclude<GroupState, "expired">;
  role: GroupRole;
  memberCount: number;
  /** null once the group is past endsAt — any non-"active" state (005 §2.3, 001 §12.2). */
  code: string | null;
}

export function toGroupListItem(
  meta: GroupMeta,
  role: GroupRole,
  memberCount: number,
  state: Exclude<GroupState, "expired">,
): GroupListItem {
  return {
    groupId: meta.groupId,
    name: meta.name,
    endsAt: meta.endsAt,
    expiryPolicy: meta.expiryPolicy,
    state,
    role,
    memberCount,
    code: state === "active" ? meta.code : null,
  };
}
