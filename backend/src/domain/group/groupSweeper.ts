// specs/002 §2.13/§4.1, specs/005 §2.4 — the daily group sweeper: the project's first
// timer-triggered function's pure domain logic. Walks the `GroupExpiry` date-bucket index
// for the 45-day catch-up window `[today − 45 … today]` (46 tiny partition scans — the
// window "generously covers groupGraceDays plus any outage backlog", never a full table
// scan), and applies each due group's expiry-policy deletion rules. Re-derives everything
// fresh from `Groups.meta` on every row via the same `deriveGroupState` pure function every
// API read path uses (005 §2.2), rather than trusting the row's own `action` label (that
// field is a diagnostic label only — the spec's per-row algorithm never branches on it) —
// this is what makes a partially-failed PATCH-time move, a partially-failed sweeper
// hard-delete, or re-running over the same bucket all self-healing/idempotent by
// construction (002 §2.13, §4.1's crash-recovery notes). Pure domain logic: no Azure/Google
// imports; the function file (groupSweeper.functions.ts) stays a thin timer registration.

import type { Clock } from "../../ports/support";
import type {
  EntitlementsRepo,
  GroupCodeRepo,
  GroupExpiryRepo,
  GroupLastKnownRepo,
  GroupMeta,
  GroupRepo,
  UserRepo,
} from "../../ports/repositories";
import { getFeatures } from "../plan";
import { deriveGroupState, graceUntilMs } from "./groupState";
import { hardDeleteGroupFootprint, wipeGroupLocationsAndCode } from "./groupDeletion";

export interface SweepGroupsDeps {
  groupExpiryRepo: GroupExpiryRepo;
  groupRepo: GroupRepo;
  groupCodeRepo: GroupCodeRepo;
  groupLastKnownRepo: GroupLastKnownRepo;
  userRepo: UserRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

/** 002 §4.1: "the window generously covers `groupGraceDays` plus any outage backlog" — the
 * documented catch-up horizon (the backlog's "45-day bucket walk"). Scans this many days
 * BEFORE today, plus today itself (46 total partition scans). */
export const SWEEP_WINDOW_DAYS = 45;

export interface SweepGroupsResult {
  /** Always SWEEP_WINDOW_DAYS + 1 (today included). */
  scannedBuckets: number;
  rowsScanned: number;
  /** GroupExpiry rows whose Groups.meta was already gone (002 §4.1 step 1) — the stray row
   * itself was cleaned; no group data existed to delete. */
  orphansCleaned: string[];
  /** Rows deleted because the group's `endsAt` is now `null` (owner removed the end date,
   * 005 §2.5; 002 §4.1 step 2 amended 2026-10-12) — only the stale row was removed. */
  staleRowsRemoved: string[];
  /** Rows moved to a later bucket because the owner extended endsAt after the row was written
   * (002 §4.1 step 2) — a stale row, self-healing. */
  rebucketed: string[];
  /** grace-policy rows at endsAt (002 §4.1 step 4, first half): locations + code wiped, row
   * re-bucketed to date(graceUntil) with action "hardDelete". */
  graceTransitioned: string[];
  /** archive-policy rows at endsAt (002 §4.1 step 5): locations + code wiped, meta/members
   * kept as a memento, expiry row deleted (never revisited). */
  archived: string[];
  /** Full hard delete (002 §4.1 step 3, or step 4's second half at graceUntil). */
  hardDeleted: string[];
  /**
   * Security fix (002 §4.1 TOCTOU race, docs/security-review-checklist.md): a row whose
   * `Groups.meta` was mutated (e.g. an owner's concurrent `PATCH endsAt` extend) or deleted
   * between this run's read and its would-be destructive action (archive/grace-wipe or hard
   * delete). Detected via `assertGroupMetaUnchanged`'s ETag check immediately before acting;
   * NOT an error — the row is simply left exactly as found and re-evaluated correctly on a
   * later sweep pass (or via the re-bucket path, if the concurrent change also moved its
   * GroupExpiry bucket).
   */
  skipped: string[];
  /** Per-row failures — the run keeps going for every other row; a failed row simply stays in
   * its bucket and is retried on the next scheduled run (it remains inside the window until
   * it ages out past SWEEP_WINDOW_DAYS). No location payloads here — groupId + error message
   * only (docs/security-review-checklist.md: timer functions must not log location data). */
  errors: { groupId: string; bucketDate: string; message: string }[];
}

function bucketDateOf(isoTimestamp: string): string {
  return isoTimestamp.slice(0, 10);
}

function bucketDatesInWindow(now: Date): string[] {
  const dates: string[] = [];
  const nowMs = now.getTime();
  for (let i = SWEEP_WINDOW_DAYS; i >= 0; i -= 1) {
    dates.push(bucketDateOf(new Date(nowMs - i * 24 * 60 * 60 * 1000).toISOString()));
  }
  return dates;
}

/** groupGraceDays is owner-governed (005 §4, mirroring 001 §9's owner-scoped
 * `maxGroupMembers` resolution in joinGroup.ts) — the sweeper has no "caller" the way an API
 * request does, so the owner's own plan is the only meaningful entitlement to resolve here. */
async function resolveGroupGraceDays(
  meta: GroupMeta,
  deps: Pick<SweepGroupsDeps, "userRepo" | "entitlementsRepo">,
): Promise<number> {
  const ownerProfile = await deps.userRepo.getProfile(meta.ownerUserId);
  const familyId = ownerProfile?.familyId ?? null;
  if (!familyId) {
    return getFeatures("free").limits.groupGraceDays;
  }
  const entitlements = await deps.entitlementsRepo.get(familyId);
  if (!entitlements) {
    // Mirrors patchGroup.ts/joinGroup.ts's INTERNAL_ERROR treatment of the same anomaly at the
    // HTTP layer: surface it as a genuine failure rather than silently inventing a plan. The
    // per-row try/catch in sweepGroups() isolates this to one row (result.errors) instead of
    // aborting the whole run.
    throw new Error(`group owner ${meta.ownerUserId}'s family ${familyId} has no entitlements record`);
  }
  return getFeatures(entitlements.subscriptionStatus).limits.groupGraceDays;
}

/**
 * Security fix (002 §4.1 TOCTOU race): re-verifies, via the SAME ETag-conditional-write idiom
 * `LastKnown`/`GroupLastKnown`/`Invites`/`Usage` already use, that `meta` has not been mutated
 * (or deleted) since this row's `getGroupMeta` read — called immediately before any of the
 * three destructive branches (archive-wipe, grace-transition-wipe, hard delete) act on that
 * snapshot. A concurrent owner `PATCH endsAt` (or a concurrent owner `DELETE`) between the read
 * and this check changes `meta`'s ETag, so `assertGroupMetaUnchanged` reports "conflict" and
 * the caller skips the row entirely — narrowing the race window from "the whole row's
 * processing" down to a single conditional write, the same residual any other ETag-guarded
 * operation in this codebase already accepts.
 */
async function verifyStillCurrent(
  groupId: string,
  meta: GroupMeta,
  deps: Pick<SweepGroupsDeps, "groupRepo">,
): Promise<boolean> {
  if (!meta.etag) {
    // Should never happen — every real getGroupMeta read populates it — but failing loud
    // beats silently skipping the safety check this function exists to perform.
    throw new Error(`GroupMeta for ${groupId} has no ETag — cannot safely verify freshness before a destructive sweep action`);
  }
  const outcome = await deps.groupRepo.assertGroupMetaUnchanged(groupId, meta.etag);
  return outcome === "ok";
}

async function processRow(
  bucketDate: string,
  groupId: string,
  now: Date,
  deps: SweepGroupsDeps,
  result: SweepGroupsResult,
): Promise<void> {
  const meta = await deps.groupRepo.getGroupMeta(groupId);
  if (!meta) {
    // 002 §4.1 step 1 — the owner already deleted the group inline; clean the orphaned row.
    await deps.groupExpiryRepo.deleteExpiryRow(bucketDate, groupId);
    result.orphansCleaned.push(groupId);
    return;
  }

  if (meta.endsAt === null) {
    // 002 §4.1 step 2 (amended 2026-10-12) — the owner removed the end date (005 §2.5), so this
    // row is stale: a group without an end date never expires and has no expiry row. Delete the
    // row and nothing else — members, code and positions of such a group are live data.
    await deps.groupExpiryRepo.deleteExpiryRow(bucketDate, groupId);
    result.staleRowsRemoved.push(groupId);
    return;
  }

  // Only grace-policy groups need groupGraceDays; skip the extra owner-plan read otherwise
  // (cost-consciousness — 000's few-euros/month target).
  const graceDays = meta.expiryPolicy === "grace" ? await resolveGroupGraceDays(meta, deps) : 0;
  const state = deriveGroupState(now, meta.endsAt, meta.expiryPolicy, graceDays);

  if (state === "active") {
    // 002 §4.1 step 2 — the owner extended endsAt since this row was written; re-bucket it.
    // If the row is already correctly bucketed at date(endsAt), it simply isn't due yet today
    // — no write needed (re-checking this daily is what makes a genuine stale move self-healing).
    const correctBucket = bucketDateOf(meta.endsAt);
    if (correctBucket !== bucketDate) {
      await deps.groupExpiryRepo.putExpiryRow(correctBucket, groupId, "expire");
      await deps.groupExpiryRepo.deleteExpiryRow(bucketDate, groupId);
      result.rebucketed.push(groupId);
    }
    return;
  }

  if (state === "archived") {
    if (!(await verifyStillCurrent(groupId, meta, deps))) {
      result.skipped.push(groupId);
      return;
    }
    // 002 §4.1 step 5 — archive: kill locations + joinability, keep the memento, never revisit.
    await wipeGroupLocationsAndCode(meta, deps);
    await deps.groupExpiryRepo.deleteExpiryRow(bucketDate, groupId);
    result.archived.push(groupId);
    return;
  }

  if (state === "ended") {
    if (!(await verifyStillCurrent(groupId, meta, deps))) {
      result.skipped.push(groupId);
      return;
    }
    // 002 §4.1 step 4 (grace, first half) — locations + joinability die now; the group itself
    // survives until graceUntil, so re-bucket the row forward with action "hardDelete".
    await wipeGroupLocationsAndCode(meta, deps);
    const hardDeleteBucket = bucketDateOf(new Date(graceUntilMs(meta.endsAt, graceDays)).toISOString());
    await deps.groupExpiryRepo.putExpiryRow(hardDeleteBucket, groupId, "hardDelete");
    if (hardDeleteBucket !== bucketDate) {
      await deps.groupExpiryRepo.deleteExpiryRow(bucketDate, groupId);
    }
    result.graceTransitioned.push(groupId);
    return;
  }

  // state === "expired" — either delete-policy at endsAt, or grace-policy at graceUntil
  // (002 §4.1 steps 3 / 4 second half): full hard delete, expiry row last.
  if (!(await verifyStillCurrent(groupId, meta, deps))) {
    result.skipped.push(groupId);
    return;
  }
  await hardDeleteGroupFootprint(meta, deps);
  await deps.groupExpiryRepo.deleteExpiryRow(bucketDate, groupId);
  result.hardDeleted.push(groupId);
}

export async function sweepGroups(deps: SweepGroupsDeps): Promise<SweepGroupsResult> {
  const now = deps.clock.now();
  const bucketDates = bucketDatesInWindow(now);

  const result: SweepGroupsResult = {
    scannedBuckets: bucketDates.length,
    rowsScanned: 0,
    orphansCleaned: [],
    staleRowsRemoved: [],
    rebucketed: [],
    graceTransitioned: [],
    archived: [],
    hardDeleted: [],
    skipped: [],
    errors: [],
  };

  for (const bucketDate of bucketDates) {
    const rows = await deps.groupExpiryRepo.listByDate(bucketDate);
    for (const row of rows) {
      result.rowsScanned += 1;
      try {
        await processRow(bucketDate, row.groupId, now, deps, result);
      } catch (err) {
        result.errors.push({
          groupId: row.groupId,
          bucketDate,
          message: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  return result;
}
