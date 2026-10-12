// specs/001 §12.4 — patch group (owner): extend/reactivate/end-early are all just "set
// endsAt to a new future instant" (005 §2.2 derived state re-derives everything from it —
// no transition writes). Pure domain logic: no Azure/Google imports. Non-membership of the
// addressed group masks as GROUP_NOT_FOUND before any role/state check (001 §12); a member
// who isn't the owner gets AUTH_FORBIDDEN (001 §1.6).

import { AppError } from "../../http/errors";
import { parseOrThrow, patchGroupRequestSchema } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type { EntitlementsRepo, GroupExpiryRepo, GroupMeta, GroupRepo, UserRepo } from "../../ports/repositories";
import { getFeatures, type Features } from "../plan";
import { countActiveGroupsWithRole } from "./activeGroupCount";
import { deriveGroupState } from "./groupState";
import { toGroupListItem, type GroupListItem } from "./groupView";

export interface PatchGroupDeps {
  groupRepo: GroupRepo;
  groupExpiryRepo: GroupExpiryRepo;
  /** Reverse index for the reactivation owner-cap count (001 §12.4). */
  userRepo: UserRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface PatchGroupInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if family-less. */
  familyId: string | null;
  groupId: string;
  body: unknown;
}

export type PatchGroupResult = GroupListItem & { features: Features };

function bucketDateOf(isoTimestamp: string): string {
  return isoTimestamp.slice(0, 10);
}

async function resolveFeatures(familyId: string | null, entitlementsRepo: EntitlementsRepo): Promise<Features> {
  if (!familyId) {
    return getFeatures("free");
  }
  const entitlements = await entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  return getFeatures(entitlements.subscriptionStatus);
}

export async function patchGroup(input: PatchGroupInput, deps: PatchGroupDeps): Promise<PatchGroupResult> {
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
    throw new AppError("AUTH_FORBIDDEN", "only the group owner may update the group");
  }

  const body = parseOrThrow(patchGroupRequestSchema, input.body);

  const features = await resolveFeatures(input.familyId, deps.entitlementsRepo);
  const now = deps.clock.now();
  const currentState = deriveGroupState(now, meta.endsAt, meta.expiryPolicy, features.limits.groupGraceDays);
  if (currentState === "archived" || currentState === "expired") {
    throw new AppError("GROUP_EXPIRED", "group can no longer be updated");
  }

  const patch: Partial<Pick<GroupMeta, "name" | "endsAt">> = {};
  if (body.name !== undefined) {
    patch.name = body.name;
  }
  if (body.endsAt !== undefined) {
    // `null` removes the end date (005 §2.5): the future/horizon checks only concern an instant.
    if (body.endsAt !== null) {
      const nowMs = now.getTime();
      const endsAtMs = new Date(body.endsAt).getTime();
      if (endsAtMs <= nowMs) {
        throw new AppError("VALIDATION_FAILED", "endsAt must be in the future", { fields: ["endsAt"] });
      }
      const maxDurationDays = features.limits.maxGroupDurationDays;
      if (maxDurationDays !== null && endsAtMs > nowMs + maxDurationDays * 24 * 60 * 60 * 1000) {
        throw new AppError("LIMIT_EXCEEDED", "endsAt exceeds the maximum group duration", {
          limit: "maxGroupDurationDays",
        });
      }
    }
    // ended (grace) -> active reactivation is a create-equivalent for the owner cap (001 §12.4):
    // the caller's OTHER active owned groups must be < maxOwnedGroups. An already-active group
    // never re-checks (it is already part of the count the cap was enforced against).
    if (currentState === "ended") {
      const otherActiveOwned = await countActiveGroupsWithRole(
        input.uid,
        "owner",
        now,
        features.limits.groupGraceDays,
        deps,
        input.groupId,
      );
      if (otherActiveOwned >= features.limits.maxOwnedGroups) {
        throw new AppError("LIMIT_EXCEEDED", "maxOwnedGroups cap reached", { limit: "maxOwnedGroups" });
      }
    }
    patch.endsAt = body.endsAt;
  }

  const updatedMeta = await deps.groupRepo.updateGroupMeta(input.groupId, patch);

  if (patch.endsAt !== undefined) {
    // Move the GroupExpiry index row (002 §2.13): insert the new bucket, delete the old one.
    // Self-healing by design — the old bucket may already be elsewhere (a prior partial move
    // or a sweeper pass), so a missing-row delete is a harmless no-op (port contract). A null
    // endsAt has no row at all: `null` deletes the old row, and null -> instant inserts one.
    const newBucket = patch.endsAt === null ? null : bucketDateOf(patch.endsAt);
    const oldBucket = meta.endsAt === null ? null : bucketDateOf(meta.endsAt);
    if (newBucket !== null) {
      await deps.groupExpiryRepo.putExpiryRow(newBucket, input.groupId, "expire");
    }
    // Never delete the row just written when the new end date stays in the same date bucket.
    if (oldBucket !== null && oldBucket !== newBucket) {
      await deps.groupExpiryRepo.deleteExpiryRow(oldBucket, input.groupId);
    }
  }

  const memberCount = (await deps.groupRepo.listMembers(input.groupId)).length;
  const newState = deriveGroupState(now, updatedMeta.endsAt, updatedMeta.expiryPolicy, features.limits.groupGraceDays);

  return {
    ...toGroupListItem(updatedMeta, "owner", memberCount, newState as Exclude<typeof newState, "expired">),
    features,
  };
}
