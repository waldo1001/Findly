// specs/001 §5.1 group fan-out side effect + specs/002 §2.12 `GroupLastKnown`. Pure domain
// logic: no Azure/Google imports. Mirrors src/domain/family/deviceFanout.ts's role for the
// family-scoped path — centralizes the "which of my groups get this fix" fan-out so
// reportLocations.ts doesn't reimplement it. After the reporter's own last-known is
// upserted (independently of whether THAT write actually changed anything), the same
// only-newer rule is applied per-group: a group's stored position is a completely separate
// row from the family LastKnown row, with its own recordedAt to compare against.
//
// Active-only (005 §2.2 — grace/ended/archived/expired groups never receive updates once
// endsAt has passed, even during grace) and position-only (005 §3 — no deviceId, batteryPct,
// source, altitude/speed/bearing; only what 002 §2.12 lists).

import type { GroupLastKnownRepo, GroupRepo, UserRepo } from "../../ports/repositories";
import { deriveGroupState } from "./groupState";

export interface GroupLocationFanoutDeps {
  userRepo: UserRepo;
  groupRepo: GroupRepo;
  groupLastKnownRepo: GroupLastKnownRepo;
}

export interface GroupLocationFanoutFix {
  lat: number;
  lon: number;
  accuracyM: number;
  recordedAt: string;
  /** The reporting device's CURRENT syncIntervalMinutes — frozen into the group position at
   * write time (002 §2.12), feeding the group map's isStale (001 §12.10). */
  syncIntervalMinutes: number;
}

/**
 * Fans the batch's newest fix out to every one of `uid`'s currently-active groups (at most
 * `features.limits.maxOwnedGroups + maxJoinedGroups` extra writes, per 001 §5.1 — those caps
 * are enforced best-effort at group create/join time, not re-checked here). A group without
 * an end date (`endsAt: null`) is always `active`, so it always receives the fan-out (005 §2.5).
 */
export async function fanOutLocationToActiveGroups(
  uid: string,
  fix: GroupLocationFanoutFix,
  receivedAt: string,
  groupGraceDays: number,
  now: Date,
  deps: GroupLocationFanoutDeps,
): Promise<void> {
  const memberships = await deps.userRepo.listGroupMemberships(uid);

  for (const membership of memberships) {
    const meta = await deps.groupRepo.getGroupMeta(membership.groupId);
    if (!meta) continue; // orphaned reverse-index row (self-healing skip, same as listGroups.ts)

    const state = deriveGroupState(now, meta.endsAt, meta.expiryPolicy, groupGraceDays);
    if (state !== "active") continue; // grace/ended/archived/expired never receive updates

    await deps.groupLastKnownRepo.upsertIfNewer(membership.groupId, {
      userId: uid,
      lat: fix.lat,
      lon: fix.lon,
      accuracyM: fix.accuracyM,
      recordedAt: fix.recordedAt,
      receivedAt,
      syncIntervalMinutes: fix.syncIntervalMinutes,
    });
  }
}
