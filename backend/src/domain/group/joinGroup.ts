// specs/001 §12.6 — join group. Pure domain logic: no Azure/Google imports. Bootstraps a
// profile if the caller has none (§1.5.3) — displayName is REQUIRED then, optional otherwise
// (defaults to the profile's, 005 §1). `maxGroupMembers` is resolved from the group OWNER's
// plan (001 §9) — the "owner upgrades -> bigger group" story without snapshotting limits.

import { AppError } from "../../http/errors";
import { joinGroupRequestSchema, parseOrThrow } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type { EntitlementsRepo, GroupCodeRepo, GroupRepo, UserRepo } from "../../ports/repositories";
import { normalizeInviteCode } from "../family/inviteCode";
import { getFeatures, type Features } from "../plan";
import { countActiveGroupsWithRole } from "./activeGroupCount";
import { deriveGroupState } from "./groupState";
import { toGroupListItem, type GroupListItem } from "./groupView";

export interface JoinGroupDeps {
  groupRepo: GroupRepo;
  groupCodeRepo: GroupCodeRepo;
  userRepo: UserRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface JoinGroupInput {
  uid: string;
  body: unknown;
}

export type JoinGroupResult = GroupListItem & { features: Features };

async function resolveFeatures(
  familyId: string | null,
  entitlementsRepo: EntitlementsRepo,
): Promise<Features> {
  if (!familyId) {
    return getFeatures("free");
  }
  const entitlements = await entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  return getFeatures(entitlements.subscriptionStatus);
}

export async function joinGroup(input: JoinGroupInput, deps: JoinGroupDeps): Promise<JoinGroupResult> {
  const body = parseOrThrow(joinGroupRequestSchema, input.body);

  const profile = await deps.userRepo.getProfile(input.uid);

  let displayName: string;
  if (profile) {
    displayName = body.displayName ?? profile.displayName;
  } else {
    if (!body.displayName) {
      throw new AppError("VALIDATION_FAILED", "displayName is required when bootstrapping a profile", {
        fields: ["displayName"],
      });
    }
    displayName = body.displayName;
  }

  const normalizedCode = normalizeInviteCode(body.code);
  const codeRecord = await deps.groupCodeRepo.getCode(normalizedCode);
  if (!codeRecord) {
    throw new AppError("GROUP_CODE_INVALID", "unknown or rotated group join code");
  }

  const meta = await deps.groupRepo.getGroupMeta(codeRecord.groupId);
  if (!meta) {
    // Orphaned code row (race with the sweeper) — masked the same as an unknown code.
    throw new AppError("GROUP_CODE_INVALID", "unknown or rotated group join code");
  }

  // `Groups.meta.code` is the authoritative live code, not the `GroupCodes` lookup alone
  // (002 §2.11, 001 §12.7 security fix): rotate's sequence is createCode -> updateGroupMeta
  // -> deleteCode, so the OLD code's GroupCodes row can still resolve for a brief window (or
  // indefinitely, if the process crashes/times out before the deleteCode cleanup runs). Once
  // updateGroupMeta has committed, meta.code makes the stale row inert regardless of whether
  // cleanup ever completes — this is what makes "the old code stops working instantly"
  // (001 §12.7) actually true, and makes rotation self-healing on crash.
  if (meta.code !== normalizedCode) {
    throw new AppError("GROUP_CODE_INVALID", "unknown or rotated group join code");
  }

  const callerFamilyId = profile?.familyId ?? null;
  const callerFeatures = await resolveFeatures(callerFamilyId, deps.entitlementsRepo);

  const now = deps.clock.now();
  const state = deriveGroupState(now, meta.endsAt, meta.expiryPolicy, callerFeatures.limits.groupGraceDays);

  // 005 §2.3 join row: expired groups mask as an invalid code (about to be swept), while
  // ended (grace)/archived groups are still resolvable but past joinability -> GROUP_EXPIRED.
  if (state === "expired") {
    throw new AppError("GROUP_CODE_INVALID", "unknown or rotated group join code");
  }
  if (state !== "active") {
    throw new AppError("GROUP_EXPIRED", "group is no longer joinable");
  }

  const existingMembership = await deps.groupRepo.getMember(meta.groupId, input.uid);
  if (existingMembership) {
    throw new AppError("GROUP_ALREADY_MEMBER", "caller is already a member of this group");
  }

  // maxJoinedGroups (005 §4, 001 §12.6): the CALLER's plan, counted over the caller's ACTIVE
  // groups with role member (owned never count here). Order: code -> expired -> already-member
  // -> maxJoinedGroups -> GROUP_FULL. Best-effort under concurrency, like the §4.1 device cap.
  const activeJoined = await countActiveGroupsWithRole(
    input.uid,
    "member",
    now,
    callerFeatures.limits.groupGraceDays,
    deps,
  );
  if (activeJoined >= callerFeatures.limits.maxJoinedGroups) {
    throw new AppError("LIMIT_EXCEEDED", "maxJoinedGroups cap reached", { limit: "maxJoinedGroups" });
  }

  const ownerProfile = await deps.userRepo.getProfile(meta.ownerUserId);
  if (!ownerProfile) {
    throw new AppError("INTERNAL_ERROR", "group owner has no profile");
  }
  const ownerFeatures = await resolveFeatures(ownerProfile.familyId, deps.entitlementsRepo);

  const currentMembers = await deps.groupRepo.listMembers(meta.groupId);
  if (currentMembers.length >= ownerFeatures.limits.maxGroupMembers) {
    throw new AppError("GROUP_FULL", "group is at capacity", { max: ownerFeatures.limits.maxGroupMembers });
  }

  const joinedAt = now.toISOString();
  await deps.groupRepo.addMember(meta.groupId, { userId: input.uid, role: "member", displayName, joinedAt });
  await deps.userRepo.addGroupMembership(input.uid, { groupId: meta.groupId, role: "member", joinedAt });
  if (!profile) {
    await deps.userRepo.createProfile(input.uid, { familyId: null, role: null, displayName });
  }

  return {
    ...toGroupListItem(meta, "member", currentMembers.length + 1, "active"),
    features: callerFeatures,
  };
}
