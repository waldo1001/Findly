// specs/002 §4.1/§6, specs/005 §2.4/§7 — the group sweeper's bucket walk and per-policy
// physical deletion, exercised against REAL Azurite Table Storage (not the in-memory fakes
// used by test/unit/domain/groupSweeper.test.ts). Requires Azurite (`npm run dev:storage`);
// run via `npm run test:integration`.
//
// Covers the §6 checklist items owned by this task: "sweeper re-run after simulated crash
// mid-hard-delete converges (expiry row deleted last)" and "expiry-row re-bucket self-heals
// after a partial PATCH endsAt move" — plus the full per-policy deletion matrix (delete/
// grace/archive) end to end through the real adapters.

import { randomUUID } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { ensureTables } from "./support/ensureStorage";
import { testGroupId, testUserId } from "./support/ids";
import { sweepGroups, type SweepGroupsDeps } from "../../src/domain/group/groupSweeper";
import { TableGroupRepo } from "../../src/adapters/tables/groupsTableRepo";
import { TableGroupCodeRepo } from "../../src/adapters/tables/groupCodesTableRepo";
import { TableGroupExpiryRepo } from "../../src/adapters/tables/groupExpiryTableRepo";
import { TableGroupLastKnownRepo } from "../../src/adapters/tables/groupLastKnownTableRepo";
import { TableUserRepo } from "../../src/adapters/tables/usersTableRepo";
import { TableEntitlementsRepo } from "../../src/adapters/tables/entitlementsTableRepo";
import { FixedClock } from "../../test/fakes/fixedClock";
import type { GroupExpiryAction, GroupMeta } from "../../src/ports/repositories";

function testCode(): string {
  return randomUUID().replace(/-/g, "").slice(0, 8).toUpperCase();
}

function buildRealDeps(now: Date): SweepGroupsDeps {
  return {
    groupExpiryRepo: new TableGroupExpiryRepo(),
    groupRepo: new TableGroupRepo(),
    groupCodeRepo: new TableGroupCodeRepo(),
    groupLastKnownRepo: new TableGroupLastKnownRepo(),
    userRepo: new TableUserRepo(),
    entitlementsRepo: new TableEntitlementsRepo(),
    clock: new FixedClock(now),
  };
}

interface SeededGroup {
  meta: GroupMeta;
  ownerId: string;
  memberIds: string[];
}

async function seedGroup(
  deps: SweepGroupsDeps,
  overrides: Partial<GroupMeta> & { endsAt: string; expiryPolicy: GroupMeta["expiryPolicy"] },
  opts: { extraMembers?: number; withLocation?: boolean } = {},
): Promise<SeededGroup> {
  const groupId = testGroupId();
  const ownerId = testUserId();
  const code = testCode();
  const createdAt = "2026-06-01T00:00:00Z";
  const meta: GroupMeta = {
    groupId,
    name: "Integration test crew",
    ownerUserId: ownerId,
    createdAt,
    code,
    ...overrides,
  };

  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(groupId, { userId: ownerId, role: "owner", displayName: "Owner", joinedAt: createdAt });
  await deps.userRepo.addGroupMembership(ownerId, { groupId, role: "owner", joinedAt: createdAt });

  const memberIds: string[] = [];
  for (let i = 0; i < (opts.extraMembers ?? 0); i += 1) {
    const memberId = testUserId();
    memberIds.push(memberId);
    await deps.groupRepo.addMember(groupId, { userId: memberId, role: "member", displayName: `Member${i}`, joinedAt: createdAt });
    await deps.userRepo.addGroupMembership(memberId, { groupId, role: "member", joinedAt: createdAt });
  }

  await deps.groupCodeRepo.createCode(code, { groupId, createdAt });

  if (opts.withLocation) {
    await deps.groupLastKnownRepo.upsertIfNewer(groupId, {
      userId: ownerId,
      lat: 51.05,
      lon: 3.72,
      accuracyM: 10,
      recordedAt: createdAt,
      receivedAt: createdAt,
      syncIntervalMinutes: 15,
    });
  }

  return { meta, ownerId, memberIds };
}

async function seedExpiryRow(deps: SweepGroupsDeps, bucketDate: string, groupId: string, action: GroupExpiryAction = "expire") {
  await deps.groupExpiryRepo.putExpiryRow(bucketDate, groupId, action);
}

/** `GroupExpiry` is partitioned by date bucket (shared across every group system-wide, unlike
 * Groups/GroupCodes/Users/GroupLastKnown which are keyed by this test's own unique ids) — so
 * assertions on a bucket must look up THIS test's own groupId rather than assume the whole
 * partition is empty/exclusive to this test (other groups, from other tests or prior runs
 * against the same persistent Azurite state, may legitimately share a date bucket). */
async function findRow(deps: SweepGroupsDeps, bucketDate: string, groupId: string) {
  const rows = await deps.groupExpiryRepo.listByDate(bucketDate);
  return rows.find((row) => row.groupId === groupId);
}

describe("integration/groupSweeper — bucket walk + physical deletion against real Azurite (specs/002 §4.1/§6)", () => {
  beforeAll(async () => {
    await ensureTables("Groups", "GroupCodes", "GroupExpiry", "GroupLastKnown", "Users", "Entitlements");
  }, 30_000);

  it("delete policy: hard-deletes meta, members, code, reverse-index rows, locations, and the expiry row itself", async () => {
    const now = new Date("2026-07-21T10:00:00Z");
    const deps = buildRealDeps(now);
    const endsAt = "2026-07-21T09:00:00Z"; // 1h before now
    const seeded = await seedGroup(deps, { endsAt, expiryPolicy: "delete" }, { extraMembers: 1, withLocation: true });
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, seeded.meta.groupId);
    // extraMembers: 1 above guarantees exactly one seeded member here (noUncheckedIndexedAccess
    // otherwise leaves memberIds[0] as `string | undefined`).
    const [firstMemberId] = seeded.memberIds;
    if (!firstMemberId) throw new Error("test setup: expected seedGroup's extraMembers:1 to seed one member");

    const result = await sweepGroups(deps);

    expect(result.hardDeleted).toContain(seeded.meta.groupId);
    expect(await deps.groupRepo.getGroupMeta(seeded.meta.groupId)).toBeNull();
    expect(await deps.groupRepo.listMembers(seeded.meta.groupId)).toEqual([]);
    expect(await deps.groupCodeRepo.getCode(seeded.meta.code)).toBeNull();
    expect(await deps.userRepo.listGroupMemberships(seeded.ownerId)).toEqual([]);
    expect(await deps.userRepo.listGroupMemberships(firstMemberId)).toEqual([]);
    expect(await deps.groupLastKnownRepo.listByGroup(seeded.meta.groupId)).toEqual([]);
    expect(await findRow(deps, bucket, seeded.meta.groupId)).toBeUndefined();
  }, 30_000);

  it("archive policy: wipes locations + code at endsAt, keeps meta/members as a memento, deletes the expiry row (never revisited)", async () => {
    const now = new Date("2026-07-21T10:00:00Z");
    const deps = buildRealDeps(now);
    const endsAt = "2026-07-21T09:00:00Z";
    const seeded = await seedGroup(deps, { endsAt, expiryPolicy: "archive" }, { extraMembers: 1, withLocation: true });
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, seeded.meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.archived).toContain(seeded.meta.groupId);
    expect(await deps.groupRepo.getGroupMeta(seeded.meta.groupId)).not.toBeNull();
    expect(await deps.groupRepo.listMembers(seeded.meta.groupId)).toHaveLength(2);
    expect(await deps.groupCodeRepo.getCode(seeded.meta.code)).toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup(seeded.meta.groupId)).toEqual([]);
    expect(await findRow(deps, bucket, seeded.meta.groupId)).toBeUndefined();
  }, 30_000);

  it("grace policy: at endsAt wipes locations + code and re-buckets the row to date(graceUntil) with action hardDelete; a later run at graceUntil then hard-deletes everything", async () => {
    const nowAtEnd = new Date("2026-07-21T10:00:00Z");
    const depsAtEnd = buildRealDeps(nowAtEnd);
    const endsAt = "2026-07-21T09:00:00Z";
    const seeded = await seedGroup(depsAtEnd, { endsAt, expiryPolicy: "grace" }, { extraMembers: 1, withLocation: true });
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(depsAtEnd, bucket, seeded.meta.groupId);

    const firstResult = await sweepGroups(depsAtEnd);

    expect(firstResult.graceTransitioned).toContain(seeded.meta.groupId);
    expect(await depsAtEnd.groupRepo.getGroupMeta(seeded.meta.groupId)).not.toBeNull();
    expect(await depsAtEnd.groupCodeRepo.getCode(seeded.meta.code)).toBeNull();
    expect(await depsAtEnd.groupLastKnownRepo.listByGroup(seeded.meta.groupId)).toEqual([]);
    expect(await findRow(depsAtEnd, bucket, seeded.meta.groupId)).toBeUndefined();
    const graceUntilBucket = "2026-07-28"; // default free-plan groupGraceDays = 7
    expect(await findRow(depsAtEnd, graceUntilBucket, seeded.meta.groupId)).toEqual({
      groupId: seeded.meta.groupId,
      action: "hardDelete",
    });

    // A second, later run finds the (real, re-bucketed) row once graceUntil has passed and
    // performs the full hard delete — same real storage, same groupId, no re-seeding.
    // graceUntil = endsAt (2026-07-21T09:00:00Z) + 7 days = 2026-07-28T09:00:00Z; pick a time
    // safely after that instant, same calendar day as the graceUntil bucket.
    const nowAtGraceUntil = new Date("2026-07-28T10:00:00Z");
    const depsAtGraceUntil = buildRealDeps(nowAtGraceUntil);
    const secondResult = await sweepGroups(depsAtGraceUntil);

    expect(secondResult.hardDeleted).toContain(seeded.meta.groupId);
    expect(await depsAtGraceUntil.groupRepo.getGroupMeta(seeded.meta.groupId)).toBeNull();
    expect(await depsAtGraceUntil.userRepo.listGroupMemberships(seeded.ownerId)).toEqual([]);
    expect(await findRow(depsAtGraceUntil, graceUntilBucket, seeded.meta.groupId)).toBeUndefined();
  }, 30_000);

  it("is idempotent after a simulated crash mid-hard-delete: meta already gone, expiry row orphaned — the re-run cleans it up without error (specs/002 §6)", async () => {
    const now = new Date("2026-07-21T10:00:00Z");
    const deps = buildRealDeps(now);
    const endsAt = "2026-07-20T00:00:00Z"; // already past
    const seeded = await seedGroup(deps, { endsAt, expiryPolicy: "delete" });
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, seeded.meta.groupId);
    // Simulate a crash that got as far as deleting Groups.meta but never reached the expiry
    // row (002 §4.1's own ordering — meta deleted before the expiry row, "last").
    await deps.groupRepo.deleteGroupMeta(seeded.meta.groupId);

    const result = await sweepGroups(deps);

    expect(result.orphansCleaned).toContain(seeded.meta.groupId);
    expect(result.hardDeleted).not.toContain(seeded.meta.groupId);
    expect(result.errors).toEqual([]);
    expect(await findRow(deps, bucket, seeded.meta.groupId)).toBeUndefined();

    // Running it again over the now-empty bucket must also be a harmless no-op.
    const rerun = await sweepGroups(deps);
    expect(rerun.orphansCleaned).not.toContain(seeded.meta.groupId);
    expect(rerun.errors).toEqual([]);
  }, 30_000);

  it("self-heals after a partial PATCH endsAt move: the row is still at the OLD bucket even though Groups.meta.endsAt was already updated to a future instant", async () => {
    const now = new Date("2026-07-21T10:00:00Z");
    const deps = buildRealDeps(now);
    const originalEndsAt = "2026-07-25T00:00:00Z";
    const seeded = await seedGroup(deps, { endsAt: originalEndsAt, expiryPolicy: "delete" });
    const staleBucket = "2026-07-10"; // where the row was written before the (partially-failed) PATCH
    await seedExpiryRow(deps, staleBucket, seeded.meta.groupId, "expire");
    // The PATCH itself already committed the new endsAt to Groups.meta — only the expiry-row
    // move half of that operation failed (002 §2.13's documented partial-move scenario).
    await deps.groupRepo.updateGroupMeta(seeded.meta.groupId, { endsAt: originalEndsAt });

    const result = await sweepGroups(deps);

    expect(result.rebucketed).toContain(seeded.meta.groupId);
    expect(await findRow(deps, staleBucket, seeded.meta.groupId)).toBeUndefined();
    const correctBucket = originalEndsAt.slice(0, 10);
    expect(await findRow(deps, correctBucket, seeded.meta.groupId)).toEqual({
      groupId: seeded.meta.groupId,
      action: "expire",
    });
    // The group itself is untouched — only its index row moved.
    expect(await deps.groupRepo.getGroupMeta(seeded.meta.groupId)).not.toBeNull();
  }, 30_000);

  it("SECURITY: TOCTOU race — a concurrent owner PATCH-extend landing between the sweeper's read and its delete is detected via a REAL ETag conflict, and the row is skipped, not deleted", async () => {
    const now = new Date("2026-07-21T10:00:00Z");
    const deps = buildRealDeps(now);
    const endsAt = "2026-07-21T09:00:00Z"; // already past -> due for hard delete
    const seeded = await seedGroup(deps, { endsAt, expiryPolicy: "delete" }, { extraMembers: 1, withLocation: true });
    const bucket = endsAt.slice(0, 10);
    await seedExpiryRow(deps, bucket, seeded.meta.groupId);

    // Capture the ETag exactly as the sweeper's own processRow does.
    const snapshot = await deps.groupRepo.getGroupMeta(seeded.meta.groupId);
    expect(snapshot?.etag).toBeTruthy();

    // Simulate the concurrent owner PATCH landing AFTER the sweeper's read but BEFORE its
    // final delete call — a REAL updateEntity against Azurite, which genuinely rotates the
    // row's ETag server-side (not a fake/simulated token).
    const extendedEndsAt = "2026-08-21T00:00:00Z";
    await deps.groupRepo.updateGroupMeta(seeded.meta.groupId, { endsAt: extendedEndsAt });

    // The sweeper's own conditional check, using the NOW-STALE captured ETag, must report a
    // genuine 412/404-mapped conflict from real Azurite — proving the precondition is
    // actually enforced server-side, not just by in-memory bookkeeping.
    const outcome = await deps.groupRepo.assertGroupMetaUnchanged(seeded.meta.groupId, snapshot!.etag!);
    expect(outcome).toBe("conflict");

    // End to end: re-run sweepGroups with a getGroupMeta wrapper that reproduces the exact
    // race (returns the sweeper's stale snapshot after the concurrent update has already
    // committed for real), confirming the full pipeline skips rather than deletes.
    const realGetGroupMeta = deps.groupRepo.getGroupMeta.bind(deps.groupRepo);
    let raceInjected = false;
    deps.groupRepo.getGroupMeta = async (groupId: string) => {
      if (groupId === seeded.meta.groupId && !raceInjected) {
        raceInjected = true;
        return snapshot; // the sweeper acts on the pre-extend snapshot it already "read"
      }
      return realGetGroupMeta(groupId);
    };

    const result = await sweepGroups(deps);

    expect(result.skipped).toContain(seeded.meta.groupId);
    expect(result.hardDeleted).not.toContain(seeded.meta.groupId);
    expect(result.errors).toEqual([]);

    // The group survives, fully intact, with the real concurrent extend actually applied.
    const survivingMeta = await realGetGroupMeta(seeded.meta.groupId);
    expect(survivingMeta?.endsAt).toBe(extendedEndsAt);
    expect(await deps.groupRepo.listMembers(seeded.meta.groupId)).toHaveLength(2);
    expect(await deps.groupCodeRepo.getCode(seeded.meta.code)).not.toBeNull();
    expect(await deps.groupLastKnownRepo.listByGroup(seeded.meta.groupId)).toHaveLength(1);
  }, 30_000);
});
