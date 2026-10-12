// specs/001 §12.1 — create group. Pure domain logic: no Azure/Google imports. Bootstraps a
// profile if the caller has none (§1.5.3) — displayName is REQUIRED then, optional otherwise
// (defaults to the profile's, 005 §1). The caller always becomes owner.

import { AppError } from "../../http/errors";
import { createGroupRequestSchema, parseOrThrow } from "../../http/validate";
import type { Clock, IdGenerator, InviteCodeGenerator } from "../../ports/support";
import type {
  EntitlementsRepo,
  GroupCodeRepo,
  GroupExpiryRepo,
  GroupMeta,
  GroupRepo,
  UserRepo,
} from "../../ports/repositories";
import { normalizeInviteCode } from "../family/inviteCode";
import { getFeatures, type Features } from "../plan";
import { countActiveGroupsWithRole } from "./activeGroupCount";
import { toGroupListItem, type GroupListItem } from "./groupView";

export interface CreateGroupDeps {
  groupRepo: GroupRepo;
  groupCodeRepo: GroupCodeRepo;
  groupExpiryRepo: GroupExpiryRepo;
  userRepo: UserRepo;
  entitlementsRepo: EntitlementsRepo;
  idGenerator: IdGenerator;
  /** Same 8-char Crockford format/normalization as family invite codes (005 §1, 001 §1.4). */
  inviteCodeGenerator: InviteCodeGenerator;
  clock: Clock;
}

export interface CreateGroupInput {
  uid: string;
  body: unknown;
}

export type CreateGroupResult = GroupListItem & { createdAt: string; features: Features };

const GROUP_ID_LENGTH = 20;
const MIN_LEAD_TIME_MS = 60 * 60 * 1000; // 1h (001 §12.1)

function bucketDateOf(isoTimestamp: string): string {
  return isoTimestamp.slice(0, 10);
}

export async function createGroup(input: CreateGroupInput, deps: CreateGroupDeps): Promise<CreateGroupResult> {
  const body = parseOrThrow(createGroupRequestSchema, input.body);

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

  const familyId = profile?.familyId ?? null;
  let features: Features;
  if (familyId) {
    const entitlements = await deps.entitlementsRepo.get(familyId);
    if (!entitlements) {
      throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
    }
    features = getFeatures(entitlements.subscriptionStatus);
  } else {
    features = getFeatures("free");
  }

  const now = deps.clock.now();
  const nowMs = now.getTime();

  // `endsAt: null` = no end date (005 §2.5): neither the +1h floor nor the duration horizon
  // applies. The horizon applies to a dated endsAt only when the plan has one (001 §9).
  if (body.endsAt !== null) {
    const endsAtMs = new Date(body.endsAt).getTime();
    if (endsAtMs < nowMs + MIN_LEAD_TIME_MS) {
      throw new AppError("VALIDATION_FAILED", "endsAt must be at least 1h from now", { fields: ["endsAt"] });
    }
    const maxDurationDays = features.limits.maxGroupDurationDays;
    if (maxDurationDays !== null && endsAtMs > nowMs + maxDurationDays * 24 * 60 * 60 * 1000) {
      throw new AppError("LIMIT_EXCEEDED", "endsAt exceeds the maximum group duration", {
        limit: "maxGroupDurationDays",
      });
    }
  }

  // maxOwnedGroups (005 §4, 001 §12.1): the caller's ACTIVE groups with role owner only —
  // ended/archived/expired never count, and joined groups are counted by joinGroup instead.
  const activeOwned = await countActiveGroupsWithRole(
    input.uid,
    "owner",
    now,
    features.limits.groupGraceDays,
    deps,
  );
  if (activeOwned >= features.limits.maxOwnedGroups) {
    throw new AppError("LIMIT_EXCEEDED", "maxOwnedGroups cap reached", { limit: "maxOwnedGroups" });
  }

  const groupId = `grp_${deps.idGenerator.next(GROUP_ID_LENGTH)}`;
  const code = normalizeInviteCode(deps.inviteCodeGenerator.next());
  const createdAt = now.toISOString();

  const meta: GroupMeta = {
    groupId,
    name: body.name,
    ownerUserId: input.uid,
    createdAt,
    endsAt: body.endsAt,
    expiryPolicy: body.expiryPolicy,
    code,
  };
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(groupId, { userId: input.uid, role: "owner", displayName, joinedAt: createdAt });
  await deps.groupCodeRepo.createCode(code, { groupId, createdAt });
  await deps.userRepo.addGroupMembership(input.uid, { groupId, role: "owner", joinedAt: createdAt });
  if (!profile) {
    await deps.userRepo.createProfile(input.uid, { familyId: null, role: null, displayName });
  }
  if (body.endsAt !== null) {
    // No GroupExpiry row for a group without an end date (002 §2.13, 005 §2.5).
    await deps.groupExpiryRepo.putExpiryRow(bucketDateOf(body.endsAt), groupId, "expire");
  }

  return {
    ...toGroupListItem(meta, "owner", 1, "active"),
    createdAt,
    features,
  };
}
