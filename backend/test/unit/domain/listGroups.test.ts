import { describe, expect, it } from "vitest";
import { listGroups } from "../../../src/domain/group/listGroups";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");

function buildDeps() {
  return {
    groupRepo: new InMemoryGroupRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    clock: new FixedClock(NOW),
  };
}

async function seedGroup(
  deps: ReturnType<typeof buildDeps>,
  uid: string,
  meta: GroupMeta,
  role: "owner" | "member",
  memberCount: number,
) {
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(meta.groupId, {
    userId: uid,
    role,
    displayName: "Whoever",
    joinedAt: meta.createdAt,
  });
  for (let i = 1; i < memberCount; i += 1) {
    await deps.groupRepo.addMember(meta.groupId, {
      userId: `other${i}`,
      role: "member",
      displayName: `Other ${i}`,
      joinedAt: meta.createdAt,
    });
  }
  await deps.userRepo.addGroupMembership(uid, { groupId: meta.groupId, role, joinedAt: meta.createdAt });
}

describe("domain/group/listGroups", () => {
  it("returns an empty list for a caller with no group memberships", async () => {
    const deps = buildDeps();

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([]);
  });

  it("lists an active group with role, memberCount, and code", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_a",
        name: "Festival crew",
        ownerUserId: "u1",
        createdAt: "2026-07-20T00:00:00Z",
        endsAt: "2026-08-02T22:00:00Z",
        expiryPolicy: "delete",
        code: "ABCD1234",
      },
      "owner",
      3,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([
      {
        groupId: "grp_a",
        name: "Festival crew",
        endsAt: "2026-08-02T22:00:00Z",
        expiryPolicy: "delete",
        state: "active",
        role: "owner",
        memberCount: 3,
        code: "ABCD1234",
      },
    ]);
  });

  it("lists a group without an end date as active with endsAt null and its code (005 §2.5)", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_a",
        name: "Standing group",
        ownerUserId: "u1",
        createdAt: "2020-01-01T00:00:00Z",
        endsAt: null,
        expiryPolicy: "delete",
        code: "ABCD1234",
      },
      "owner",
      2,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([
      {
        groupId: "grp_a",
        name: "Standing group",
        endsAt: null,
        expiryPolicy: "delete",
        state: "active",
        role: "owner",
        memberCount: 2,
        code: "ABCD1234",
      },
    ]);
  });

  it("filters out a delete-policy group past endsAt (expired)", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_a",
        name: "Old crew",
        ownerUserId: "u1",
        createdAt: "2026-01-01T00:00:00Z",
        endsAt: "2026-01-02T00:00:00Z",
        expiryPolicy: "delete",
        code: "ABCD1234",
      },
      "owner",
      1,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([]);
  });

  it("includes a grace-policy group as ended with code: null once past endsAt (still within grace)", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_a",
        name: "Grace crew",
        ownerUserId: "u1",
        createdAt: "2026-07-10T00:00:00Z",
        endsAt: "2026-07-20T00:00:00Z", // 1 day before NOW, grace = 7 days -> still ended
        expiryPolicy: "grace",
        code: "ABCD1234",
      },
      "owner",
      2,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([
      {
        groupId: "grp_a",
        name: "Grace crew",
        endsAt: "2026-07-20T00:00:00Z",
        expiryPolicy: "grace",
        state: "ended",
        role: "owner",
        memberCount: 2,
        code: null,
      },
    ]);
  });

  it("filters out a grace-policy group past graceUntil (expired)", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_a",
        name: "Long-gone crew",
        ownerUserId: "u1",
        createdAt: "2026-01-01T00:00:00Z",
        endsAt: "2026-01-02T00:00:00Z", // graceUntil = 2026-01-09, long past NOW
        expiryPolicy: "grace",
        code: "ABCD1234",
      },
      "owner",
      1,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([]);
  });

  it("includes an archive-policy group as archived with code: null", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_a",
        name: "Memento crew",
        ownerUserId: "u1",
        createdAt: "2026-01-01T00:00:00Z",
        endsAt: "2026-01-02T00:00:00Z",
        expiryPolicy: "archive",
        code: "ABCD1234",
      },
      "member",
      4,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([
      {
        groupId: "grp_a",
        name: "Memento crew",
        endsAt: "2026-01-02T00:00:00Z",
        expiryPolicy: "archive",
        state: "archived",
        role: "member",
        memberCount: 4,
        code: null,
      },
    ]);
  });

  it("tolerates an orphaned reverse-index row (group meta missing — self-healing skip)", async () => {
    const deps = buildDeps();
    await deps.userRepo.addGroupMembership("u1", {
      groupId: "grp_gone",
      role: "owner",
      joinedAt: NOW.toISOString(),
    });

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups).toEqual([]);
  });

  it("lists multiple groups (owned + joined) together", async () => {
    const deps = buildDeps();
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_owned",
        name: "Owned",
        ownerUserId: "u1",
        createdAt: "2026-07-20T00:00:00Z",
        endsAt: "2026-08-02T22:00:00Z",
        expiryPolicy: "delete",
        code: "OWNED0001",
      },
      "owner",
      1,
    );
    await seedGroup(
      deps,
      "u1",
      {
        groupId: "grp_joined",
        name: "Joined",
        ownerUserId: "u9",
        createdAt: "2026-07-20T00:00:00Z",
        endsAt: "2026-08-02T22:00:00Z",
        expiryPolicy: "delete",
        code: "JOINED001",
      },
      "member",
      2,
    );

    const result = await listGroups({ uid: "u1", familyId: null }, deps);

    expect(result.groups.map((g) => g.groupId).sort()).toEqual(["grp_joined", "grp_owned"]);
  });

  describe("features resolution", () => {
    it("returns implicit free features for a family-less caller", async () => {
      const deps = buildDeps();

      const result = await listGroups({ uid: "u1", familyId: null }, deps);

      expect(result.features).toEqual(getFeatures("free"));
    });

    it("resolves features from the family's entitlements when the caller has a family", async () => {
      const deps = buildDeps();
      deps.entitlementsRepo.seed("fam_x", { subscriptionStatus: "active", updatedAt: "2026-07-01T00:00:00Z" });

      const result = await listGroups({ uid: "u1", familyId: "fam_x" }, deps);

      expect(result.features).toEqual(getFeatures("active"));
    });

    it("throws INTERNAL_ERROR when the caller's family has no Entitlements record", async () => {
      const deps = buildDeps();
      // Deliberately NOT seeding entitlementsRepo for fam_no_ent.

      await expectAppError(listGroups({ uid: "u1", familyId: "fam_no_ent" }, deps), "INTERNAL_ERROR");
    });
  });
});
