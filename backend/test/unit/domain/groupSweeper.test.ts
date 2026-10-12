import { describe, expect, it } from "vitest";
import { sweepGroups, SWEEP_WINDOW_DAYS } from "../../../src/domain/group/groupSweeper";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupCodeRepo } from "../../fakes/inMemoryGroupCodeRepo";
import { InMemoryGroupExpiryRepo } from "../../fakes/inMemoryGroupExpiryRepo";
import { InMemoryGroupLastKnownRepo } from "../../fakes/inMemoryGroupLastKnownRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import type { GroupExpiryAction, GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;

function daysFromNow(days: number): string {
  return new Date(NOW.getTime() + days * DAY_MS).toISOString().slice(0, 10);
}

function buildDeps() {
  return {
    groupExpiryRepo: new InMemoryGroupExpiryRepo(),
    groupRepo: new InMemoryGroupRepo(),
    groupCodeRepo: new InMemoryGroupCodeRepo(),
    groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    clock: new FixedClock(NOW),
  };
}

function baseMeta(overrides: Partial<GroupMeta> = {}): GroupMeta {
  return {
    groupId: "grp_a",
    name: "Festival crew",
    ownerUserId: "u1",
    createdAt: "2026-06-01T00:00:00Z",
    endsAt: "2026-07-21T09:00:00Z", // 1h before NOW by default
    expiryPolicy: "delete",
    code: "ABCD1234",
    ...overrides,
  };
}

async function seedGroup(
  deps: ReturnType<typeof buildDeps>,
  meta: GroupMeta,
  opts: { members?: string[]; withLocations?: boolean } = {},
) {
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(meta.groupId, {
    userId: meta.ownerUserId,
    role: "owner",
    displayName: "Eric",
    joinedAt: meta.createdAt,
  });
  await deps.userRepo.addGroupMembership(meta.ownerUserId, {
    groupId: meta.groupId,
    role: "owner",
    joinedAt: meta.createdAt,
  });
  for (const memberId of opts.members ?? []) {
    await deps.groupRepo.addMember(meta.groupId, {
      userId: memberId,
      role: "member",
      displayName: memberId,
      joinedAt: meta.createdAt,
    });
    await deps.userRepo.addGroupMembership(memberId, { groupId: meta.groupId, role: "member", joinedAt: meta.createdAt });
  }
  await deps.groupCodeRepo.createCode(meta.code, { groupId: meta.groupId, createdAt: meta.createdAt });
  if (opts.withLocations) {
    await deps.groupLastKnownRepo.upsertIfNewer(meta.groupId, {
      userId: meta.ownerUserId,
      lat: 51.05,
      lon: 3.72,
      accuracyM: 10,
      recordedAt: meta.createdAt,
      receivedAt: meta.createdAt,
      syncIntervalMinutes: 15,
    });
  }
}

async function seedExpiryRow(
  deps: ReturnType<typeof buildDeps>,
  bucketDate: string,
  groupId: string,
  action: GroupExpiryAction = "expire",
) {
  await deps.groupExpiryRepo.putExpiryRow(bucketDate, groupId, action);
}

describe("domain/group/groupSweeper sweepGroups", () => {
  it("scans exactly SWEEP_WINDOW_DAYS + 1 buckets (today-45..today inclusive)", async () => {
    const deps = buildDeps();
    const result = await sweepGroups(deps);
    expect(SWEEP_WINDOW_DAYS).toBe(45);
    expect(result.scannedBuckets).toBe(46);
    expect(result.rowsScanned).toBe(0);
  });

  it("processes a row at exactly today-45 (window's oldest edge)", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(-45) + "T00:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    await seedExpiryRow(deps, daysFromNow(-45), meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toContain("grp_a");
    expect(result.rowsScanned).toBe(1);
    expect(result.rebucketed).toEqual([]);
    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
  });

  it("does NOT process a row at today-46 (just outside the window)", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(-46) + "T00:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    await seedExpiryRow(deps, daysFromNow(-46), meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).not.toContain("grp_a");
    expect(result.rowsScanned).toBe(0);
    expect(await deps.groupRepo.getGroupMeta("grp_a")).not.toBeNull();
  });

  it("cleans an orphaned expiry row when Groups.meta is already gone (owner deleted inline)", async () => {
    const deps = buildDeps();
    await seedExpiryRow(deps, daysFromNow(-1), "grp_gone");

    const result = await sweepGroups(deps);

    expect(result.orphansCleaned).toContain("grp_gone");
    expect(await deps.groupExpiryRepo.listByDate(daysFromNow(-1))).toEqual([]);
  });

  it("deletes a stale expiry row whose meta has endsAt null and touches NOTHING else (005 §2.5, 002 §4.1 step 2)", async () => {
    const deps = buildDeps();
    // Every policy: a null endsAt never expires, whatever the policy, however old the row.
    for (const [i, policy] of (["delete", "grace", "archive"] as const).entries()) {
      const groupId = `grp_noend${i}`;
      const meta = baseMeta({ groupId, endsAt: null, expiryPolicy: policy, code: `NOEND00${i}` });
      await seedGroup(deps, meta, { members: [`m${i}`], withLocations: true });
      await seedExpiryRow(deps, daysFromNow(-3), groupId);
    }

    const result = await sweepGroups(deps);

    expect(result.rowsScanned).toBe(3);
    expect(result.staleRowsRemoved.sort()).toEqual(["grp_noend0", "grp_noend1", "grp_noend2"]);
    expect(result.hardDeleted).toEqual([]);
    expect(result.archived).toEqual([]);
    expect(result.graceTransitioned).toEqual([]);
    expect(result.rebucketed).toEqual([]);
    expect(result.skipped).toEqual([]);
    expect(result.errors).toEqual([]);
    expect(deps.groupExpiryRepo.size()).toBe(0);
    for (let i = 0; i < 3; i += 1) {
      const groupId = `grp_noend${i}`;
      expect(await deps.groupRepo.getGroupMeta(groupId)).not.toBeNull();
      expect(await deps.groupRepo.listMembers(groupId)).toHaveLength(2);
      expect(await deps.groupCodeRepo.getCode(`NOEND00${i}`)).not.toBeNull();
      expect(await deps.groupLastKnownRepo.listByGroup(groupId)).toHaveLength(1);
      expect(await deps.userRepo.listGroupMemberships(`m${i}`)).toHaveLength(1);
    }
  });

  it("re-buckets a stale row when the owner extended endsAt into the future (self-healing)", async () => {
    const deps = buildDeps();
    const newEndsAt = daysFromNow(10) + "T00:00:00Z";
    const meta = baseMeta({ endsAt: newEndsAt, expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    // The row is still at the OLD (stale) bucket — simulating a partially-failed PATCH move.
    await seedExpiryRow(deps, daysFromNow(-5), meta.groupId, "expire");

    const result = await sweepGroups(deps);

    expect(result.rebucketed).toContain("grp_a");
    expect(await deps.groupExpiryRepo.listByDate(daysFromNow(-5))).toEqual([]);
    const moved = await deps.groupExpiryRepo.listByDate(daysFromNow(10));
    expect(moved).toEqual([{ groupId: "grp_a", action: "expire" }]);
    // Group itself untouched.
    expect(await deps.groupRepo.getGroupMeta("grp_a")).not.toBeNull();
  });

  it("leaves an active group's correctly-bucketed row untouched when it simply isn't due yet today", async () => {
    const deps = buildDeps();
    // endsAt is later TODAY — the row is already at the correct (today) bucket.
    const endsAt = new Date(NOW.getTime() + 6 * 60 * 60 * 1000).toISOString(); // +6h, same UTC day
    const meta = baseMeta({ endsAt, expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    const today = daysFromNow(0);
    await seedExpiryRow(deps, today, meta.groupId, "expire");

    const result = await sweepGroups(deps);

    expect(result.rebucketed).not.toContain("grp_a");
    expect(result.hardDeleted).not.toContain("grp_a");
    expect(result.orphansCleaned).not.toContain("grp_a");
    expect(await deps.groupExpiryRepo.listByDate(today)).toEqual([{ groupId: "grp_a", action: "expire" }]);
  });

  it("delete policy: hard-deletes everything at exactly endsAt", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta, { members: ["u9"], withLocations: true });
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toEqual(["grp_a"]);
    expect(result.skipped).toEqual([]);
    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
    expect(await deps.groupRepo.listMembers("grp_a")).toEqual([]);
    expect(await deps.groupCodeRepo.getCode("ABCD1234")).toBeNull();
    expect(await deps.userRepo.listGroupMemberships("u1")).toEqual([]);
    expect(await deps.userRepo.listGroupMemberships("u9")).toEqual([]);
    expect(await deps.groupLastKnownRepo.listByGroup("grp_a")).toEqual([]);
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([]);
  });

  it("archive policy: wipes locations + code at endsAt but keeps meta/members as a memento, and never revisits", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "archive" });
    await seedGroup(deps, meta, { members: ["u9"], withLocations: true });
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.archived).toEqual(["grp_a"]);
    expect(await deps.groupRepo.getGroupMeta("grp_a")).not.toBeNull();
    expect(await deps.groupRepo.listMembers("grp_a")).toHaveLength(2);
    expect(await deps.groupCodeRepo.getCode("ABCD1234")).toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup("grp_a")).toEqual([]);
    // Expiry row deleted, not re-bucketed — archive is "never revisited" (002 §4.1 step 5).
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([]);
  });

  it("grace policy at endsAt (still within grace): wipes locations + code, keeps meta/members, re-buckets to date(graceUntil) with action hardDelete", async () => {
    const deps = buildDeps();
    const endsAt = daysFromNow(0) + "T09:00:00Z";
    const meta = baseMeta({ endsAt, expiryPolicy: "grace" });
    await seedGroup(deps, meta, { members: ["u9"], withLocations: true });
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.graceTransitioned).toEqual(["grp_a"]);
    expect(result.errors).toEqual([]);
    expect(await deps.groupRepo.getGroupMeta("grp_a")).not.toBeNull();
    expect(await deps.groupRepo.listMembers("grp_a")).toHaveLength(2);
    expect(await deps.groupCodeRepo.getCode("ABCD1234")).toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup("grp_a")).toEqual([]);
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([]);
    const graceUntilBucket = daysFromNow(7); // default free-plan groupGraceDays = 7
    const movedRow = await deps.groupExpiryRepo.listByDate(graceUntilBucket);
    expect(movedRow).toEqual([{ groupId: "grp_a", action: "hardDelete" }]);
  });

  it("grace policy: when the row is already at the graceUntil bucket (edge case), the transition leaves it in place instead of deleting it", async () => {
    const deps = buildDeps();
    // endsAt 7 days ago at 23:00 -> graceUntil = today at 23:00 (default groupGraceDays=7) ->
    // NOW (today 10:00) < graceUntil, so state is "ended", and date(graceUntil) == today.
    const endsAt = daysFromNow(-7) + "T23:00:00Z";
    const meta = baseMeta({ endsAt, expiryPolicy: "grace" });
    await seedGroup(deps, meta);
    const todayBucket = daysFromNow(0); // == the computed hardDeleteBucket for this input
    // Seed the row directly at the bucket the transition would compute, rather than at
    // date(endsAt) — exercises the "already correctly bucketed" guard (put-then-delete on the
    // SAME key would otherwise erase the row instead of upserting its action in place).
    await seedExpiryRow(deps, todayBucket, meta.groupId, "expire");

    const result = await sweepGroups(deps);

    expect(result.graceTransitioned).toEqual(["grp_a"]);
    expect(await deps.groupExpiryRepo.listByDate(todayBucket)).toEqual([
      { groupId: "grp_a", action: "hardDelete" },
    ]);
  });

  it("grace policy at graceUntil (grace period over): full hard delete", async () => {
    const deps = buildDeps();
    // endsAt was 7 days ago (default groupGraceDays=7), so NOW is exactly graceUntil.
    const endsAt = daysFromNow(-7) + "T10:00:00Z";
    const meta = baseMeta({ endsAt, expiryPolicy: "grace" });
    await seedGroup(deps, meta, { members: ["u9"] });
    const bucket = daysFromNow(0); // row was already moved here by a prior sweep run
    await seedExpiryRow(deps, bucket, meta.groupId, "hardDelete");

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toEqual(["grp_a"]);
    expect(result.errors).toEqual([]);
    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([]);
  });

  it("resolves groupGraceDays from the OWNER's plan (family owner, family-less irrelevant here since PLAN_MATRIX free===active)", async () => {
    const deps = buildDeps();
    deps.userRepo.seed("u1", { familyId: "fam_x", role: "parent", displayName: "Eric" });
    deps.entitlementsRepo.seed("fam_x", { subscriptionStatus: "active", updatedAt: "2026-01-01T00:00:00Z" });
    const endsAt = daysFromNow(0) + "T09:00:00Z";
    const meta = baseMeta({ endsAt, expiryPolicy: "grace", ownerUserId: "u1" });
    await seedGroup(deps, meta);
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.graceTransitioned).toEqual(["grp_a"]);
    expect(result.errors).toEqual([]);
    const graceUntilBucket = daysFromNow(7);
    expect(await deps.groupExpiryRepo.listByDate(graceUntilBucket)).toEqual([{ groupId: "grp_a", action: "hardDelete" }]);
  });

  it("records a per-row error (does not throw) when the owner's family has no entitlements record", async () => {
    const deps = buildDeps();
    deps.userRepo.seed("u1", { familyId: "fam_missing", role: "parent", displayName: "Eric" });
    // Deliberately no deps.entitlementsRepo.seed(...) — the family exists per the profile but
    // its Entitlements row is missing (data anomaly).
    const endsAt = daysFromNow(0) + "T09:00:00Z";
    const meta = baseMeta({ endsAt, expiryPolicy: "grace", ownerUserId: "u1" });
    await seedGroup(deps, meta);
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.graceTransitioned).toEqual([]);
    expect(result.errors).toEqual([
      { groupId: "grp_a", bucketDate: bucket, message: "group owner u1's family fam_missing has no entitlements record" },
    ]);
    // Left exactly as found — retried on the next scheduled run.
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([{ groupId: "grp_a", action: "expire" }]);
  });

  it("never resolves groupGraceDays for non-grace policies, even when the owner's plan would fail to resolve", async () => {
    const deps = buildDeps();
    // If the ternary dispatch ever called resolveGroupGraceDays for a delete-policy group, this
    // owner's missing entitlements record would make it throw — proving it was never called.
    deps.userRepo.seed("u1", { familyId: "fam_missing", role: "parent", displayName: "Eric" });
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete", ownerUserId: "u1" });
    await seedGroup(deps, meta);
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toEqual(["grp_a"]);
    expect(result.errors).toEqual([]);
  });

  it("is idempotent: running twice over an already-swept bucket silently skips (no error, no double effect)", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const first = await sweepGroups(deps);
    expect(first.hardDeleted).toEqual(["grp_a"]);

    const second = await sweepGroups(deps);
    expect(second.hardDeleted).toEqual([]);
    expect(second.errors).toEqual([]);
    expect(second.rowsScanned).toBe(0);
  });

  it("is idempotent after a simulated crash mid-hard-delete (meta gone, expiry row orphaned)", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(-1) + "T00:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);
    // Simulate a crash that deleted meta but left the expiry row behind.
    deps.groupRepo.deleteMetaOnlyForTest(meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.orphansCleaned).toEqual(["grp_a"]);
    expect(result.hardDeleted).toEqual([]);
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([]);
  });

  it("isolates a per-row failure: one throwing group does not block others in the same run", async () => {
    const deps = buildDeps();
    const boomMeta = baseMeta({ groupId: "grp_boom", endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete" });
    const okMeta = baseMeta({ groupId: "grp_ok", endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, okMeta);
    await seedExpiryRow(deps, okMeta.endsAt!.slice(0, 10), okMeta.groupId);
    await seedExpiryRow(deps, boomMeta.endsAt!.slice(0, 10), boomMeta.groupId);
    // grp_boom has an expiry row but NO seeded group meta/members/code — getGroupMeta returns
    // null for it normally (which would just be the orphan path, not a throw), so instead
    // force a genuine failure via a broken groupRepo wrapping the real one.
    const realGetGroupMeta = deps.groupRepo.getGroupMeta.bind(deps.groupRepo);
    deps.groupRepo.getGroupMeta = async (groupId: string) => {
      if (groupId === "grp_boom") throw new Error("simulated storage failure");
      return realGetGroupMeta(groupId);
    };

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toEqual(["grp_ok"]);
    expect(result.errors).toEqual([
      { groupId: "grp_boom", bucketDate: boomMeta.endsAt!.slice(0, 10), message: "simulated storage failure" },
    ]);
  });

  // Security fix (docs/security-review-checklist.md finding): TOCTOU race between a
  // concurrent owner PATCH-extend and the sweeper's stale read. Each test below wraps
  // groupRepo.getGroupMeta so that, right after capturing the snapshot the sweeper will act
  // on, it injects a REAL concurrent mutation (via the same fake's updateGroupMeta, which
  // rotates the meta row's simulated ETag exactly like a real owner PATCH would) before
  // returning that now-stale snapshot to the sweeper — reproducing "a PATCH lands between the
  // sweeper's read and its final delete for that exact row". assertGroupMetaUnchanged must
  // then detect the ETag mismatch and the row must be skipped, not acted on.

  it("SECURITY: skips (does not hard-delete) when a concurrent PATCH-extend lands between the sweeper's read and its delete", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta, { members: ["u9"], withLocations: true });
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const realGetGroupMeta = deps.groupRepo.getGroupMeta.bind(deps.groupRepo);
    const extendedEndsAt = daysFromNow(30) + "T00:00:00Z";
    let raceInjected = false;
    deps.groupRepo.getGroupMeta = async (groupId: string) => {
      const snapshot = await realGetGroupMeta(groupId);
      if (groupId === meta.groupId && !raceInjected) {
        raceInjected = true;
        // The concurrent owner PATCH: rotates meta's ETag via the SAME fake, exactly like a
        // real Table Storage conditional update would.
        await deps.groupRepo.updateGroupMeta(groupId, { endsAt: extendedEndsAt });
      }
      return snapshot; // the sweeper still acts on its (now-stale) snapshot
    };

    const result = await sweepGroups(deps);

    expect(result.skipped).toEqual(["grp_a"]);
    expect(result.hardDeleted).toEqual([]);
    expect(result.errors).toEqual([]);
    // The group survives, fully intact, with the concurrent extend actually applied.
    const survivingMeta = await realGetGroupMeta(meta.groupId);
    expect(survivingMeta?.endsAt).toBe(extendedEndsAt);
    expect(await deps.groupRepo.listMembers(meta.groupId)).toHaveLength(2);
    expect(await deps.groupCodeRepo.getCode(meta.code)).not.toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup(meta.groupId)).toHaveLength(1);
  });

  it("SECURITY: skips (does not wipe locations/code) when a concurrent PATCH lands between the read and an archive-policy wipe", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "archive" });
    await seedGroup(deps, meta, { withLocations: true });
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const realGetGroupMeta = deps.groupRepo.getGroupMeta.bind(deps.groupRepo);
    let raceInjected = false;
    deps.groupRepo.getGroupMeta = async (groupId: string) => {
      const snapshot = await realGetGroupMeta(groupId);
      if (groupId === meta.groupId && !raceInjected) {
        raceInjected = true;
        await deps.groupRepo.updateGroupMeta(groupId, { name: "renamed concurrently" });
      }
      return snapshot;
    };

    const result = await sweepGroups(deps);

    expect(result.skipped).toEqual(["grp_a"]);
    expect(result.archived).toEqual([]);
    expect(await deps.groupCodeRepo.getCode(meta.code)).not.toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup(meta.groupId)).toHaveLength(1);
  });

  it("SECURITY: skips (does not wipe locations/code or re-bucket) when a concurrent PATCH lands between the read and a grace-transition wipe", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "grace" });
    await seedGroup(deps, meta, { withLocations: true });
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const realGetGroupMeta = deps.groupRepo.getGroupMeta.bind(deps.groupRepo);
    let raceInjected = false;
    deps.groupRepo.getGroupMeta = async (groupId: string) => {
      const snapshot = await realGetGroupMeta(groupId);
      if (groupId === meta.groupId && !raceInjected) {
        raceInjected = true;
        await deps.groupRepo.updateGroupMeta(groupId, { name: "renamed concurrently" });
      }
      return snapshot;
    };

    const result = await sweepGroups(deps);

    expect(result.skipped).toEqual(["grp_a"]);
    expect(result.graceTransitioned).toEqual([]);
    expect(await deps.groupCodeRepo.getCode(meta.code)).not.toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup(meta.groupId)).toHaveLength(1);
    // Left exactly where found — not re-bucketed to a hardDelete-action row.
    expect(await deps.groupExpiryRepo.listByDate(bucket)).toEqual([{ groupId: "grp_a", action: "expire" }]);
  });

  it("throws (isolated to result.errors) if a GroupMeta snapshot is somehow missing its ETag", async () => {
    const deps = buildDeps();
    const meta = baseMeta({ endsAt: daysFromNow(0) + "T09:00:00Z", expiryPolicy: "delete" });
    await seedGroup(deps, meta);
    const bucket = meta.endsAt!.slice(0, 10);
    await seedExpiryRow(deps, bucket, meta.groupId);

    const realGetGroupMeta = deps.groupRepo.getGroupMeta.bind(deps.groupRepo);
    deps.groupRepo.getGroupMeta = async (groupId: string) => {
      const snapshot = await realGetGroupMeta(groupId);
      return snapshot ? { ...snapshot, etag: undefined } : snapshot;
    };

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toEqual([]);
    expect(result.skipped).toEqual([]);
    expect(result.errors).toEqual([
      {
        groupId: "grp_a",
        bucketDate: bucket,
        message: "GroupMeta for grp_a has no ETag — cannot safely verify freshness before a destructive sweep action",
      },
    ]);
    // Untouched — the row stays exactly as found, retried on the next run.
    expect(await deps.groupRepo.getGroupMeta("grp_a")).not.toBeNull();
  });
});
