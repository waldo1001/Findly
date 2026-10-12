import { describe, expect, it } from "vitest";
import { patchGroup } from "../../../src/domain/group/patchGroup";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupExpiryRepo } from "../../fakes/inMemoryGroupExpiryRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import { useLimitOverride } from "../../support/planOverride";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import type { GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");

function buildDeps() {
  return {
    groupRepo: new InMemoryGroupRepo(),
    groupExpiryRepo: new InMemoryGroupExpiryRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    userRepo: new InMemoryUserRepo(),
    clock: new FixedClock(NOW),
  };
}

const ACTIVE_META: GroupMeta = {
  groupId: "grp_a",
  name: "Festival crew",
  ownerUserId: "u1",
  createdAt: "2026-07-20T00:00:00Z",
  endsAt: "2026-08-02T22:00:00Z",
  expiryPolicy: "delete",
  code: "ABCD1234",
};

async function seed(deps: ReturnType<typeof buildDeps>, meta: GroupMeta) {
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(meta.groupId, {
    userId: meta.ownerUserId,
    role: "owner",
    displayName: "Eric",
    joinedAt: meta.createdAt,
  });
  await deps.groupRepo.addMember(meta.groupId, {
    userId: "u9",
    role: "member",
    displayName: "Noor",
    joinedAt: meta.createdAt,
  });
  if (meta.endsAt !== null) {
    await deps.groupExpiryRepo.putExpiryRow(meta.endsAt!.slice(0, 10), meta.groupId, "expire");
  }
  await deps.userRepo.addGroupMembership(meta.ownerUserId, { groupId: meta.groupId, role: "owner", joinedAt: meta.createdAt });
}

describe("domain/group/patchGroup", () => {
  it("throws GROUP_NOT_FOUND for a nonexistent group", async () => {
    const deps = buildDeps();

    await expectAppError(
      patchGroup({ uid: "u1", familyId: null, groupId: "grp_nope", body: { name: "x" } }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws GROUP_NOT_FOUND for a caller who is not a member (masked)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      patchGroup({ uid: "u404", familyId: null, groupId: "grp_a", body: { name: "x" } }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws AUTH_FORBIDDEN when the caller is a member but not the owner", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      patchGroup({ uid: "u9", familyId: null, groupId: "grp_a", body: { name: "x" } }, deps),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws GROUP_NOT_FOUND when meta is gone but an orphaned member row survives (crash mid-sweep)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    deps.groupRepo.deleteMetaOnlyForTest("grp_a");

    await expectAppError(
      patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { name: "x" } }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws VALIDATION_FAILED when neither name nor endsAt is present", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: {} }, deps),
      "VALIDATION_FAILED",
    );
  });

  it("renames the group without touching endsAt or the expiry row", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    const result = await patchGroup(
      { uid: "u1", familyId: null, groupId: "grp_a", body: { name: "Festival crew 2026" } },
      deps,
    );

    expect(result).toMatchObject({
      groupId: "grp_a",
      name: "Festival crew 2026",
      endsAt: ACTIVE_META.endsAt,
      state: "active",
      role: "owner",
      memberCount: 2,
    });
    expect(deps.groupExpiryRepo.get(ACTIVE_META.endsAt!.slice(0, 10), "grp_a")).toEqual({
      bucketDate: ACTIVE_META.endsAt!.slice(0, 10),
      groupId: "grp_a",
      action: "expire",
    });
  });

  it("leaves the name untouched when only endsAt is patched", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    const newEndsAt = "2026-08-10T22:00:00Z";

    const result = await patchGroup(
      { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: newEndsAt } },
      deps,
    );

    expect(result.name).toBe(ACTIVE_META.name);
  });

  it("extends endsAt: updates meta and moves the GroupExpiry row to the new bucket", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    const newEndsAt = "2026-08-10T22:00:00Z";

    const result = await patchGroup(
      { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: newEndsAt } },
      deps,
    );

    expect(result.endsAt).toBe(newEndsAt);
    expect(result.state).toBe("active");
    expect(deps.groupExpiryRepo.get(ACTIVE_META.endsAt!.slice(0, 10), "grp_a")).toBeUndefined();
    expect(deps.groupExpiryRepo.get(newEndsAt.slice(0, 10), "grp_a")).toEqual({
      bucketDate: newEndsAt.slice(0, 10),
      groupId: "grp_a",
      action: "expire",
    });
  });

  it("keeps the GroupExpiry row when the new endsAt falls in the SAME date bucket (no put-then-delete)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META); // 2026-08-02T22:00Z
    const sameDay = "2026-08-02T23:30:00Z";

    await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: sameDay } }, deps);

    expect(deps.groupExpiryRepo.get("2026-08-02", "grp_a")).toEqual({
      bucketDate: "2026-08-02",
      groupId: "grp_a",
      action: "expire",
    });
  });

  it("reactivates an ended (grace) group by extending endsAt into the future", async () => {
    const deps = buildDeps();
    const graceMeta: GroupMeta = { ...ACTIVE_META, endsAt: "2026-07-20T00:00:00Z", expiryPolicy: "grace" };
    await seed(deps, graceMeta);
    const newEndsAt = "2026-08-15T00:00:00Z";

    const result = await patchGroup(
      { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: newEndsAt } },
      deps,
    );

    expect(result.state).toBe("active");
    expect(result.endsAt).toBe(newEndsAt);
  });

  it('accepts an endsAt just over 1 minute from now as the "end the group now" convenience (001 §12.4)', async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    const soon = new Date(NOW.getTime() + 60_000).toISOString();

    const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: soon } }, deps);

    expect(result.endsAt).toBe(soon);
    expect(result.state).toBe("active");
  });

  it("throws VALIDATION_FAILED when endsAt is not strictly greater than now", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: NOW.toISOString() } }, deps),
      "VALIDATION_FAILED",
      { fields: ["endsAt"] },
    );
  });

  it("throws VALIDATION_FAILED when endsAt is in the past", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-07-01T00:00:00Z" } },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["endsAt"] },
    );
  });

  describe("with a numeric maxGroupDurationDays (30)", () => {
    useLimitOverride({ maxGroupDurationDays: 30 });

    it("throws LIMIT_EXCEEDED (maxGroupDurationDays) when endsAt exceeds the horizon", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);
      const tooFar = new Date(NOW.getTime() + 31 * 24 * 60 * 60 * 1000).toISOString();

      await expectAppError(
        patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: tooFar } }, deps),
        "LIMIT_EXCEEDED",
        { limit: "maxGroupDurationDays" },
      );
    });

    it("accepts endsAt exactly at the maxGroupDurationDays boundary (<=, not <)", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);
      const atBoundary = new Date(NOW.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();

      const result = await patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: atBoundary } },
        deps,
      );

      expect(result.endsAt).toBe(atBoundary);
    });

    it("never applies the horizon to endsAt: null (005 §2.5)", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);

      const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps);

      expect(result.endsAt).toBeNull();
    });
  });

  it("accepts any future dated endsAt when maxGroupDurationDays is null (shipped free plan)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    const tenYears = new Date(NOW.getTime() + 3650 * 24 * 60 * 60 * 1000).toISOString();

    const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: tenYears } }, deps);

    expect(result.endsAt).toBe(tenYears);
  });

  it("throws GROUP_EXPIRED (410) when patching an archived group", async () => {
    const deps = buildDeps();
    const archiveMeta: GroupMeta = { ...ACTIVE_META, endsAt: "2026-01-01T00:00:00Z", expiryPolicy: "archive" };
    await seed(deps, archiveMeta);

    await expectAppError(
      patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-08-01T00:00:00Z" } },
        deps,
      ),
      "GROUP_EXPIRED",
    );
  });

  it("throws GROUP_EXPIRED (410) when patching an expired (not yet swept) delete-policy group", async () => {
    const deps = buildDeps();
    const expiredMeta: GroupMeta = { ...ACTIVE_META, endsAt: "2026-01-02T00:00:00Z", expiryPolicy: "delete" };
    await seed(deps, expiredMeta);

    await expectAppError(
      patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-08-01T00:00:00Z" } },
        deps,
      ),
      "GROUP_EXPIRED",
    );
  });

  describe("removing / setting an end date (005 §2.5, 001 §12.4)", () => {
    it("accepts { endsAt: null } as 'at least one field' and removes the end date + deletes the expiry row", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);

      const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps);

      expect(result.endsAt).toBeNull();
      expect(result.state).toBe("active");
      expect(result.code).toBe("ABCD1234");
      expect((await deps.groupRepo.getGroupMeta("grp_a"))?.endsAt).toBeNull();
      expect(deps.groupExpiryRepo.get(ACTIVE_META.endsAt!.slice(0, 10), "grp_a")).toBeUndefined();
      expect(deps.groupExpiryRepo.size()).toBe(0);
    });

    it("{ endsAt: null } on a group that already has none is an idempotent no-op", async () => {
      const deps = buildDeps();
      await seed(deps, { ...ACTIVE_META, endsAt: null });

      const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps);

      expect(result.endsAt).toBeNull();
      expect(result.state).toBe("active");
      expect(deps.groupExpiryRepo.size()).toBe(0);
    });

    it("an ABSENT endsAt key leaves a null endsAt unchanged (rename only)", async () => {
      const deps = buildDeps();
      await seed(deps, { ...ACTIVE_META, endsAt: null });

      const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { name: "Renamed" } }, deps);

      expect(result).toMatchObject({ name: "Renamed", endsAt: null, state: "active" });
      expect(deps.groupExpiryRepo.size()).toBe(0);
    });

    it("sets an end date on a no-end group: inserts the expiry row at date(endsAt)", async () => {
      const deps = buildDeps();
      await seed(deps, { ...ACTIVE_META, endsAt: null });
      const newEndsAt = "2026-08-10T22:00:00Z";

      const result = await patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: newEndsAt } },
        deps,
      );

      expect(result.endsAt).toBe(newEndsAt);
      expect(deps.groupExpiryRepo.get("2026-08-10", "grp_a")).toEqual({
        bucketDate: "2026-08-10",
        groupId: "grp_a",
        action: "expire",
      });
      expect(deps.groupExpiryRepo.size()).toBe(1);
    });

    it("throws VALIDATION_FAILED for a non-datetime, non-null endsAt", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);

      await expectAppError(
        patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "soon" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["endsAt"] },
      );
    });

    it("still answers GROUP_EXPIRED (410) for { endsAt: null } on an archived group", async () => {
      const deps = buildDeps();
      await seed(deps, { ...ACTIVE_META, endsAt: "2026-01-01T00:00:00Z", expiryPolicy: "archive" });

      await expectAppError(
        patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps),
        "GROUP_EXPIRED",
      );
    });
  });

  describe("grace reactivation checks maxOwnedGroups over the caller's OTHER active owned groups (001 §12.4)", () => {
    const ENDED_META: GroupMeta = { ...ACTIVE_META, endsAt: "2026-07-20T00:00:00Z", expiryPolicy: "grace" };

    async function seedOtherOwned(deps: ReturnType<typeof buildDeps>, count: number, overrides: Partial<GroupMeta> = {}) {
      for (let i = 0; i < count; i += 1) {
        const groupId = `grp_other${i}${overrides.expiryPolicy ?? ""}`;
        await deps.groupRepo.createGroupMeta({
          ...ACTIVE_META,
          groupId,
          code: `OTH${i}`,
          ...overrides,
        });
        await deps.userRepo.addGroupMembership("u1", { groupId, role: "owner", joinedAt: "2026-07-01T00:00:00Z" });
      }
    }

    it("refuses reactivation to a future instant at 5 other active owned groups: LIMIT_EXCEEDED maxOwnedGroups", async () => {
      const deps = buildDeps();
      await seed(deps, ENDED_META);
      await seedOtherOwned(deps, 5);

      await expectAppError(
        patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-08-15T00:00:00Z" } }, deps),
        "LIMIT_EXCEEDED",
        { limit: "maxOwnedGroups" },
      );
      expect((await deps.groupRepo.getGroupMeta("grp_a"))?.endsAt).toBe(ENDED_META.endsAt);
    });

    it("refuses reactivation to null at 5 other active owned groups", async () => {
      const deps = buildDeps();
      await seed(deps, ENDED_META);
      await seedOtherOwned(deps, 5);

      await expectAppError(
        patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps),
        "LIMIT_EXCEEDED",
        { limit: "maxOwnedGroups" },
      );
    });

    it("allows reactivation to an instant at 4 other active owned groups", async () => {
      const deps = buildDeps();
      await seed(deps, ENDED_META);
      await seedOtherOwned(deps, 4);

      const result = await patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-08-15T00:00:00Z" } },
        deps,
      );

      expect(result.state).toBe("active");
    });

    it("allows reactivation to null at 4 other active owned groups; moves the expiry row away", async () => {
      const deps = buildDeps();
      await seed(deps, ENDED_META);
      await seedOtherOwned(deps, 4);

      const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps);

      expect(result).toMatchObject({ state: "active", endsAt: null });
      expect(deps.groupExpiryRepo.get("2026-07-20", "grp_a")).toBeUndefined();
    });

    it("does not count other ended/archived owned groups or joined groups", async () => {
      const deps = buildDeps();
      await seed(deps, ENDED_META);
      await seedOtherOwned(deps, 3);
      await seedOtherOwned(deps, 1, { endsAt: "2026-01-01T00:00:00Z", expiryPolicy: "archive" });
      await seedOtherOwned(deps, 1, { endsAt: "2026-07-19T00:00:00Z", expiryPolicy: "grace" });
      for (let i = 0; i < 5; i += 1) {
        await deps.groupRepo.createGroupMeta({ ...ACTIVE_META, groupId: `grp_joined${i}`, ownerUserId: "zz", code: `JJ${i}` });
        await deps.userRepo.addGroupMembership("u1", { groupId: `grp_joined${i}`, role: "member", joinedAt: "2026-07-01T00:00:00Z" });
      }

      const result = await patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-08-15T00:00:00Z" } },
        deps,
      );

      expect(result.state).toBe("active");
    });

    it("never re-checks the cap for an already-active group (extend / remove end date)", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);
      await seedOtherOwned(deps, 5);

      const extended = await patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: "2026-08-10T00:00:00Z" } },
        deps,
      );
      const removed = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { endsAt: null } }, deps);

      expect(extended.endsAt).toBe("2026-08-10T00:00:00Z");
      expect(removed.endsAt).toBeNull();
    });

    it("a rename of an ended group at the cap is allowed (no reactivation, no cap check)", async () => {
      const deps = buildDeps();
      await seed(deps, ENDED_META);
      await seedOtherOwned(deps, 5);

      const result = await patchGroup({ uid: "u1", familyId: null, groupId: "grp_a", body: { name: "Keepsake" } }, deps);

      expect(result).toMatchObject({ name: "Keepsake", state: "ended" });
    });
  });

  describe("features resolution", () => {
    it("returns implicit free features for a family-less owner", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);

      const result = await patchGroup(
        { uid: "u1", familyId: null, groupId: "grp_a", body: { name: "New name" } },
        deps,
      );

      expect(result.features).toEqual(getFeatures("free"));
    });

    it("throws INTERNAL_ERROR when the owner's family has no Entitlements record", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);

      await expectAppError(
        patchGroup(
          { uid: "u1", familyId: "fam_no_ent", groupId: "grp_a", body: { name: "New name" } },
          deps,
        ),
        "INTERNAL_ERROR",
      );
    });

    it("resolves features from the owner's family entitlements when they have a family", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);
      deps.entitlementsRepo.seed("fam_x", { subscriptionStatus: "active", updatedAt: "2026-07-01T00:00:00Z" });

      const result = await patchGroup(
        { uid: "u1", familyId: "fam_x", groupId: "grp_a", body: { name: "New name" } },
        deps,
      );

      expect(result.features).toEqual(getFeatures("active"));
    });
  });
});
