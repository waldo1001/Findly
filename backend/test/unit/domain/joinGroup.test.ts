import { describe, expect, it } from "vitest";
import { joinGroup } from "../../../src/domain/group/joinGroup";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupCodeRepo } from "../../fakes/inMemoryGroupCodeRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");

function buildDeps() {
  return {
    groupRepo: new InMemoryGroupRepo(),
    groupCodeRepo: new InMemoryGroupCodeRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    clock: new FixedClock(NOW),
  };
}

const ACTIVE_META: GroupMeta = {
  groupId: "grp_a",
  name: "Festival crew",
  ownerUserId: "owner1",
  createdAt: "2026-07-20T00:00:00Z",
  endsAt: "2026-08-02T22:00:00Z",
  expiryPolicy: "delete",
  code: "ABCD1234",
};

async function seedGroup(deps: ReturnType<typeof buildDeps>, meta: GroupMeta) {
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(meta.groupId, {
    userId: meta.ownerUserId,
    role: "owner",
    displayName: "Owner",
    joinedAt: meta.createdAt,
  });
  await deps.groupCodeRepo.createCode(meta.code, { groupId: meta.groupId, createdAt: meta.createdAt });
  // Invariant: the owner always has a profile (createGroup bootstraps one) — a family-less
  // one by default here, unless the test overrides it (e.g. the owner-plan resolution test).
  if (!(await deps.userRepo.getProfile(meta.ownerUserId))) {
    deps.userRepo.seed(meta.ownerUserId, { familyId: null, role: null, displayName: "Owner" });
  }
}

describe("domain/group/joinGroup", () => {
  it("joins an active group; caller becomes member; memberCount incremented; code echoed", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);

    const result = await joinGroup({ uid: "u2", body: { code: "abcd-1234", displayName: "Noor" } }, deps);

    expect(result).toMatchObject({
      groupId: "grp_a",
      name: "Festival crew",
      endsAt: "2026-08-02T22:00:00Z",
      expiryPolicy: "delete",
      state: "active",
      role: "member",
      memberCount: 2,
      code: "ABCD1234",
    });
  });

  it("normalizes a lowercase, hyphenated code before lookup", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);

    const result = await joinGroup({ uid: "u2", body: { code: "abcd-1234", displayName: "Noor" } }, deps);

    expect(result.groupId).toBe("grp_a");
  });

  it("persists the member row with the chosen per-group displayName", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);

    await joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps);

    const member = await deps.groupRepo.getMember("grp_a", "u2");
    expect(member).toEqual({ userId: "u2", role: "member", displayName: "Noor", joinedAt: NOW.toISOString() });
  });

  it("writes the Users group: reverse-index row for the joiner", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);

    await joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps);

    const memberships = await deps.userRepo.listGroupMemberships("u2");
    expect(memberships).toEqual([{ groupId: "grp_a", role: "member", joinedAt: NOW.toISOString() }]);
  });

  it("throws GROUP_CODE_INVALID for an unknown code", async () => {
    const deps = buildDeps();

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: "NOSUCH01", displayName: "Noor" } }, deps),
      "GROUP_CODE_INVALID",
    );
  });

  it("throws GROUP_CODE_INVALID when the code row is orphaned (group meta missing)", async () => {
    const deps = buildDeps();
    await deps.groupCodeRepo.createCode("ORPHAN01", { groupId: "grp_gone", createdAt: NOW.toISOString() });

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: "ORPHAN01", displayName: "Noor" } }, deps),
      "GROUP_CODE_INVALID",
    );
  });

  it("throws GROUP_CODE_INVALID for the OLD code once meta.code has rotated, even before the old GroupCodes row is cleaned up (001 §12.7 rotate-atomicity security fix, 002 §2.11 crash window)", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);
    // Simulate the exact crash window between rotateGroupCode's updateGroupMeta (step 2) and
    // deleteCode (step 3): the new code row exists and meta.code already points to it, but the
    // OLD code's GroupCodes row is still sitting there un-cleaned-up.
    await deps.groupCodeRepo.createCode("NEWCODE1", { groupId: "grp_a", createdAt: NOW.toISOString() });
    await deps.groupRepo.updateGroupMeta("grp_a", { code: "NEWCODE1" });
    // deliberately NOT calling deps.groupCodeRepo.deleteCode(ACTIVE_META.code) here.

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: ACTIVE_META.code, displayName: "Noor" } }, deps),
      "GROUP_CODE_INVALID",
    );
  });

  it("accepts the NEW code once meta.code has rotated, in that same crash window", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);
    await deps.groupCodeRepo.createCode("NEWCODE1", { groupId: "grp_a", createdAt: NOW.toISOString() });
    await deps.groupRepo.updateGroupMeta("grp_a", { code: "NEWCODE1" });

    const result = await joinGroup({ uid: "u2", body: { code: "NEWCODE1", displayName: "Noor" } }, deps);

    expect(result.groupId).toBe("grp_a");
  });

  it("throws GROUP_CODE_INVALID (not GROUP_EXPIRED) for an expired delete-policy group (005 §2.3 join row)", async () => {
    const deps = buildDeps();
    await seedGroup(deps, { ...ACTIVE_META, endsAt: "2026-01-02T00:00:00Z", expiryPolicy: "delete" });

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
      "GROUP_CODE_INVALID",
    );
  });

  it("throws GROUP_CODE_INVALID (not GROUP_EXPIRED) for a grace group past graceUntil", async () => {
    const deps = buildDeps();
    await seedGroup(deps, { ...ACTIVE_META, endsAt: "2026-01-01T00:00:00Z", expiryPolicy: "grace" });

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
      "GROUP_CODE_INVALID",
    );
  });

  it("throws GROUP_EXPIRED for an ended (grace, still within grace) group", async () => {
    const deps = buildDeps();
    await seedGroup(deps, { ...ACTIVE_META, endsAt: "2026-07-20T00:00:00Z", expiryPolicy: "grace" });

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
      "GROUP_EXPIRED",
    );
  });

  it("throws GROUP_EXPIRED for an archived group", async () => {
    const deps = buildDeps();
    await seedGroup(deps, { ...ACTIVE_META, endsAt: "2026-01-01T00:00:00Z", expiryPolicy: "archive" });

    await expectAppError(
      joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
      "GROUP_EXPIRED",
    );
  });

  it("throws GROUP_ALREADY_MEMBER when the caller is already a member", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);

    await expectAppError(
      joinGroup({ uid: "owner1", body: { code: "ABCD1234", displayName: "Owner again" } }, deps),
      "GROUP_ALREADY_MEMBER",
    );
  });

  describe("owner-plan GROUP_FULL capacity (001 §9/§12.6)", () => {
    it("throws GROUP_FULL with details.max once the roster hits the owner's plan maxGroupMembers cap", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      // Free plan cap is 200; owner + 199 members = 200 already (at cap).
      for (let i = 0; i < 199; i += 1) {
        await deps.groupRepo.addMember("grp_a", {
          userId: `existing${i}`,
          role: "member",
          displayName: `Existing ${i}`,
          joinedAt: ACTIVE_META.createdAt,
        });
      }

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
        "GROUP_FULL",
        { max: 200 },
      );
    });

    it("resolves maxGroupMembers from the OWNER's plan, not the joiner's", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      // Owner belongs to a family on the (currently identical) "active" plan — the joiner
      // has no profile/family at all. The cap must come from the owner's resolved plan.
      deps.userRepo.seed("owner1", { familyId: "fam_owner", role: "parent", displayName: "Owner" });
      deps.entitlementsRepo.seed("fam_owner", { subscriptionStatus: "active", updatedAt: "2026-07-01T00:00:00Z" });

      const result = await joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps);

      expect(result.role).toBe("member");
    });
  });

  describe("profile bootstrapping (001 §1.5.3/§12.6)", () => {
    it("creates a family-less profile when the caller has none, using the request displayName", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);

      await joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps);

      const profile = await deps.userRepo.getProfile("u2");
      expect(profile).toEqual({ familyId: null, role: null, displayName: "Noor" });
    });

    it("throws VALIDATION_FAILED for a missing displayName when the caller has no profile", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: "ABCD1234" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["displayName"] },
      );
    });

    it("does NOT recreate the profile when the caller already has one", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      deps.userRepo.seed("u2", { familyId: "fam_x", role: "member", displayName: "Noor Home" });
      deps.entitlementsRepo.seed("fam_x", { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });

      await joinGroup({ uid: "u2", body: { code: "ABCD1234" } }, deps);

      const profile = await deps.userRepo.getProfile("u2");
      expect(profile).toEqual({ familyId: "fam_x", role: "member", displayName: "Noor Home" });
    });

    it("defaults the per-group displayName to the existing profile's when the request omits it", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      deps.userRepo.seed("u2", { familyId: null, role: null, displayName: "Group-only Noor" });

      await joinGroup({ uid: "u2", body: { code: "ABCD1234" } }, deps);

      const member = await deps.groupRepo.getMember("grp_a", "u2");
      expect(member?.displayName).toBe("Group-only Noor");
    });

    it("uses the request displayName over the profile's when both are present (per-group override)", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      deps.userRepo.seed("u2", { familyId: null, role: null, displayName: "Home name" });

      await joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Festival name" } }, deps);

      const member = await deps.groupRepo.getMember("grp_a", "u2");
      expect(member?.displayName).toBe("Festival name");
    });
  });

  describe("validation (001 §12.6)", () => {
    it('throws VALIDATION_FAILED with details.fields: ["code"] for a missing code', async () => {
      const deps = buildDeps();

      await expectAppError(
        joinGroup({ uid: "u2", body: { displayName: "Noor" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["code"] },
      );
    });

    it("throws VALIDATION_FAILED for a non-object body", async () => {
      const deps = buildDeps();

      await expectAppError(joinGroup({ uid: "u2", body: "nope" }, deps), "VALIDATION_FAILED", {
        fields: ["(root)"],
      });
    });

    it("throws VALIDATION_FAILED for a code over 16 chars, never reaching the code repo", async () => {
      const deps = buildDeps();

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: "x".repeat(17), displayName: "Noor" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["code"] },
      );
    });

    it.each([
      ["a/b", "forward slash"],
      ["a\\b", "backslash"],
      ["a#b", "hash"],
      ["a?b", "question mark"],
    ])("throws VALIDATION_FAILED for a code containing a forbidden %s, never reaching the code repo", async (malformed) => {
      const deps = buildDeps();

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: malformed, displayName: "Noor" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["code"] },
      );
    });
  });

  describe("features resolution", () => {
    it("returns implicit free features for a family-less joiner", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);

      const result = await joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps);

      expect(result.features).toEqual(getFeatures("free"));
    });

    it("resolves features from the joiner's own family entitlements when they have a family", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      deps.userRepo.seed("u2", { familyId: "fam_x", role: "member", displayName: "Noor" });
      deps.entitlementsRepo.seed("fam_x", { subscriptionStatus: "active", updatedAt: "2026-07-01T00:00:00Z" });

      const result = await joinGroup({ uid: "u2", body: { code: "ABCD1234" } }, deps);

      expect(result.features).toEqual(getFeatures("active"));
    });

    it("throws INTERNAL_ERROR when the joiner's family has no Entitlements record", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      deps.userRepo.seed("u2", { familyId: "fam_no_ent", role: "member", displayName: "Noor" });
      // Deliberately NOT seeding entitlementsRepo for fam_no_ent.

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: "ABCD1234" } }, deps),
        "INTERNAL_ERROR",
      );
    });
  });

  describe("owner invariants (defense-in-depth)", () => {
    it("throws INTERNAL_ERROR when the group owner has no profile at all", async () => {
      const deps = buildDeps();
      // Seed the group WITHOUT going through seedGroup's owner-profile default, to simulate
      // a data-integrity violation (createGroup always bootstraps one in practice).
      await deps.groupRepo.createGroupMeta(ACTIVE_META);
      await deps.groupRepo.addMember(ACTIVE_META.groupId, {
        userId: ACTIVE_META.ownerUserId,
        role: "owner",
        displayName: "Owner",
        joinedAt: ACTIVE_META.createdAt,
      });
      await deps.groupCodeRepo.createCode(ACTIVE_META.code, {
        groupId: ACTIVE_META.groupId,
        createdAt: ACTIVE_META.createdAt,
      });

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
        "INTERNAL_ERROR",
      );
    });

    it("throws INTERNAL_ERROR when the group owner's family has no Entitlements record", async () => {
      const deps = buildDeps();
      await seedGroup(deps, ACTIVE_META);
      deps.userRepo.seed("owner1", { familyId: "fam_owner_no_ent", role: "parent", displayName: "Owner" });
      // Deliberately NOT seeding entitlementsRepo for fam_owner_no_ent.

      await expectAppError(
        joinGroup({ uid: "u2", body: { code: "ABCD1234", displayName: "Noor" } }, deps),
        "INTERNAL_ERROR",
      );
    });
  });

  it("normalizes displayName at write time before storing (strips a right-to-left override, 001 §1.4/B29)", async () => {
    const deps = buildDeps();
    await seedGroup(deps, ACTIVE_META);

    const result = await joinGroup(
      { uid: "u2", body: { code: "abcd-1234", displayName: "Noor‮cirE" } },
      deps,
    );

    expect(result.role).toBe("member");
    const members = await deps.groupRepo.listMembers("grp_a");
    const joined = members.find((m) => m.userId === "u2");
    expect(joined?.displayName).toBe("NoorcirE");
  });

});
