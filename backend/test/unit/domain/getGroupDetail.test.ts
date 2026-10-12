import { describe, expect, it } from "vitest";
import { getGroupDetail } from "../../../src/domain/group/getGroupDetail";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");

function buildDeps() {
  return {
    groupRepo: new InMemoryGroupRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
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
}

describe("domain/group/getGroupDetail", () => {
  it("throws GROUP_NOT_FOUND for a nonexistent group", async () => {
    const deps = buildDeps();

    await expectAppError(
      getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_nope" }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws GROUP_NOT_FOUND for a caller who is not a member (masked, indistinguishable from nonexistent)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      getGroupDetail({ uid: "u404", familyId: null, groupId: "grp_a" }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws GROUP_NOT_FOUND when meta is gone but an orphaned member row survives (crash mid-sweep)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    deps.groupRepo.deleteMetaOnlyForTest("grp_a");

    await expectAppError(
      getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_a" }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("returns the full roster and code for an active group (owner)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    const result = await getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(result).toMatchObject({
      groupId: "grp_a",
      name: "Festival crew",
      endsAt: "2026-08-02T22:00:00Z",
      expiryPolicy: "delete",
      state: "active",
      role: "owner",
      memberCount: 2,
      code: "ABCD1234",
      createdAt: "2026-07-20T00:00:00Z",
    });
    expect(result.members).toEqual([
      { userId: "u1", role: "owner", displayName: "Eric", joinedAt: "2026-07-20T00:00:00Z" },
      { userId: "u9", role: "member", displayName: "Noor", joinedAt: "2026-07-20T00:00:00Z" },
    ]);
  });

  it("returns a group without an end date as active with endsAt null and the roster (005 §2.5)", async () => {
    const deps = buildDeps();
    await seed(deps, { ...ACTIVE_META, endsAt: null });

    const result = await getGroupDetail({ uid: "u9", familyId: null, groupId: "grp_a" }, deps);

    expect(result).toMatchObject({ endsAt: null, state: "active", code: "ABCD1234" });
    expect(result.members).not.toBeNull();
  });

  it("returns the full roster for an active group (non-owner member)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    const result = await getGroupDetail({ uid: "u9", familyId: null, groupId: "grp_a" }, deps);

    expect(result.role).toBe("member");
    expect(result.members).not.toBeNull();
  });

  it("hides the roster (members: null) during grace for a non-owner member", async () => {
    const deps = buildDeps();
    const graceMeta: GroupMeta = {
      ...ACTIVE_META,
      endsAt: "2026-07-20T00:00:00Z", // 1 day before NOW, grace 7 days -> "ended"
      expiryPolicy: "grace",
    };
    await seed(deps, graceMeta);

    const result = await getGroupDetail({ uid: "u9", familyId: null, groupId: "grp_a" }, deps);

    expect(result.state).toBe("ended");
    expect(result.members).toBeNull();
    expect(result.code).toBeNull();
  });

  it("shows the full roster during grace for the owner", async () => {
    const deps = buildDeps();
    const graceMeta: GroupMeta = {
      ...ACTIVE_META,
      endsAt: "2026-07-20T00:00:00Z",
      expiryPolicy: "grace",
    };
    await seed(deps, graceMeta);

    const result = await getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(result.state).toBe("ended");
    expect(result.members).not.toBeNull();
    expect(result.members).toHaveLength(2);
  });

  it("shows the full roster (memento) for an archived group regardless of role", async () => {
    const deps = buildDeps();
    const archiveMeta: GroupMeta = {
      ...ACTIVE_META,
      endsAt: "2026-01-01T00:00:00Z",
      expiryPolicy: "archive",
    };
    await seed(deps, archiveMeta);

    const result = await getGroupDetail({ uid: "u9", familyId: null, groupId: "grp_a" }, deps);

    expect(result.state).toBe("archived");
    expect(result.members).not.toBeNull();
    expect(result.code).toBeNull();
  });

  it("throws GROUP_EXPIRED for a delete-policy group past endsAt", async () => {
    const deps = buildDeps();
    const expiredMeta: GroupMeta = {
      ...ACTIVE_META,
      endsAt: "2026-01-02T00:00:00Z",
      expiryPolicy: "delete",
    };
    await seed(deps, expiredMeta);

    await expectAppError(
      getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_a" }, deps),
      "GROUP_EXPIRED",
    );
  });

  it("throws GROUP_EXPIRED for a grace-policy group past graceUntil, even for the owner", async () => {
    const deps = buildDeps();
    const expiredMeta: GroupMeta = {
      ...ACTIVE_META,
      endsAt: "2026-01-01T00:00:00Z", // graceUntil 2026-01-08, long past NOW
      expiryPolicy: "grace",
    };
    await seed(deps, expiredMeta);

    await expectAppError(
      getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_a" }, deps),
      "GROUP_EXPIRED",
    );
  });

  describe("features resolution", () => {
    it("returns implicit free features for a family-less caller", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);

      const result = await getGroupDetail({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

      expect(result.features).toEqual(getFeatures("free"));
    });

    it("resolves features from the family's entitlements when the caller has a family", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);
      deps.entitlementsRepo.seed("fam_x", { subscriptionStatus: "active", updatedAt: "2026-07-01T00:00:00Z" });

      const result = await getGroupDetail({ uid: "u1", familyId: "fam_x", groupId: "grp_a" }, deps);

      expect(result.features).toEqual(getFeatures("active"));
    });

    it("throws INTERNAL_ERROR when the caller's family has no Entitlements record", async () => {
      const deps = buildDeps();
      await seed(deps, ACTIVE_META);
      // Deliberately NOT seeding entitlementsRepo for fam_no_ent.

      await expectAppError(
        getGroupDetail({ uid: "u1", familyId: "fam_no_ent", groupId: "grp_a" }, deps),
        "INTERNAL_ERROR",
      );
    });
  });
});
