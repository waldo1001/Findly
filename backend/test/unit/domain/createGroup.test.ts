import { describe, expect, it } from "vitest";
import { createGroup } from "../../../src/domain/group/createGroup";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupCodeRepo } from "../../fakes/inMemoryGroupCodeRepo";
import { InMemoryGroupExpiryRepo } from "../../fakes/inMemoryGroupExpiryRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { SeqIdGenerator } from "../../fakes/seqIdGenerator";
import { SeqInviteCodeGenerator } from "../../fakes/seqInviteCodeGenerator";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import { useLimitOverride } from "../../support/planOverride";
import type { GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");
const VALID_ENDS_AT = "2026-08-02T22:00:00Z"; // well within [now+1h, now+30d]

function buildDeps() {
  return {
    groupRepo: new InMemoryGroupRepo(),
    groupCodeRepo: new InMemoryGroupCodeRepo(),
    groupExpiryRepo: new InMemoryGroupExpiryRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    idGenerator: new SeqIdGenerator(),
    inviteCodeGenerator: new SeqInviteCodeGenerator(),
    clock: new FixedClock(NOW),
  };
}

const VALID_BODY = {
  name: "Festival crew",
  endsAt: VALID_ENDS_AT,
  expiryPolicy: "delete" as const,
  displayName: "Eric",
};

describe("domain/group/createGroup", () => {
  it("creates the group; caller becomes owner; state active; memberCount 1", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    expect(result.name).toBe("Festival crew");
    expect(result.endsAt).toBe(VALID_ENDS_AT);
    expect(result.expiryPolicy).toBe("delete");
    expect(result.state).toBe("active");
    expect(result.role).toBe("owner");
    expect(result.memberCount).toBe(1);
    expect(result.createdAt).toBe(NOW.toISOString());
  });

  it("generates grp_ + 20 chars [A-Za-z0-9] via the IdGenerator port", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    expect(result.groupId).toMatch(/^grp_[A-Za-z0-9]{20}$/);
  });

  it("generates an 8-char canonical join code via the InviteCodeGenerator port (005 §1)", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    expect(result.code).toBe("00000001");
  });

  it("persists Groups.meta with the owner and denormalized code (via the repo fake)", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    const meta = await deps.groupRepo.getGroupMeta(result.groupId);
    // `etag` is the fake's simulated Table Storage concurrency token (B12 security fix,
    // 002 §4.1 TOCTOU) — populated on every read, irrelevant to this test's assertion.
    expect(meta).toEqual({
      groupId: result.groupId,
      name: "Festival crew",
      ownerUserId: "u1",
      createdAt: NOW.toISOString(),
      endsAt: VALID_ENDS_AT,
      expiryPolicy: "delete",
      code: result.code,
      etag: expect.any(String),
    });
  });

  it("persists the owner member row with the chosen per-group displayName", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    const member = await deps.groupRepo.getMember(result.groupId, "u1");
    expect(member).toEqual({
      userId: "u1",
      role: "owner",
      displayName: "Eric",
      joinedAt: NOW.toISOString(),
    });
  });

  it("persists the GroupCodes row pointing at the new group", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    // GroupListItem.code is `string | null` (null once the group is no longer "active" —
    // groupView.ts) but a freshly created group is always active, so it's a real code here.
    if (!result.code) throw new Error("test setup: a freshly created group must be active and carry a code");
    const codeRecord = await deps.groupCodeRepo.getCode(result.code);
    expect(codeRecord).toEqual({ groupId: result.groupId, createdAt: NOW.toISOString() });
  });

  it("writes the Users group: reverse-index row for the owner (002 §2.2)", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    const memberships = await deps.userRepo.listGroupMemberships("u1");
    expect(memberships).toEqual([{ groupId: result.groupId, role: "owner", joinedAt: NOW.toISOString() }]);
  });

  it("writes the GroupExpiry row bucketed to date(endsAt) with action expire (002 §2.13)", async () => {
    const deps = buildDeps();

    const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

    const row = deps.groupExpiryRepo.get("2026-08-02", result.groupId);
    expect(row).toEqual({ bucketDate: "2026-08-02", groupId: result.groupId, action: "expire" });
  });

  describe("profile bootstrapping (001 §1.5.3/§12.1)", () => {
    it("creates a family-less profile when the caller has none, using the request displayName", async () => {
      const deps = buildDeps();

      await createGroup({ uid: "u1", body: VALID_BODY }, deps);

      const profile = await deps.userRepo.getProfile("u1");
      expect(profile).toEqual({ familyId: null, role: null, displayName: "Eric" });
    });

    it("throws VALIDATION_FAILED for a missing displayName when the caller has no profile", async () => {
      const deps = buildDeps();

      await expectAppError(
        createGroup({ uid: "u1", body: { name: "Crew", endsAt: VALID_ENDS_AT, expiryPolicy: "delete" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["displayName"] },
      );
    });

    it("does NOT recreate the profile when the caller already has one (family member)", async () => {
      const deps = buildDeps();
      deps.userRepo.seed("u1", { familyId: "fam_existing0000000000", role: "parent", displayName: "Eric W." });
      deps.entitlementsRepo.seed("fam_existing0000000000", {
        subscriptionStatus: "free",
        updatedAt: "2026-07-01T00:00:00Z",
      });

      await createGroup({ uid: "u1", body: { name: "Crew", endsAt: VALID_ENDS_AT, expiryPolicy: "delete" } }, deps);

      const profile = await deps.userRepo.getProfile("u1");
      expect(profile).toEqual({ familyId: "fam_existing0000000000", role: "parent", displayName: "Eric W." });
    });

    it("defaults the per-group displayName to the existing profile's when the request omits it", async () => {
      const deps = buildDeps();
      deps.userRepo.seed("u1", { familyId: null, role: null, displayName: "Group-only Noor" });

      const result = await createGroup(
        { uid: "u1", body: { name: "Crew", endsAt: VALID_ENDS_AT, expiryPolicy: "delete" } },
        deps,
      );

      const member = await deps.groupRepo.getMember(result.groupId, "u1");
      expect(member?.displayName).toBe("Group-only Noor");
    });

    it("uses the request displayName over the profile's when both are present (per-group override)", async () => {
      const deps = buildDeps();
      deps.userRepo.seed("u1", { familyId: null, role: null, displayName: "Home name" });

      const result = await createGroup(
        { uid: "u1", body: { name: "Crew", endsAt: VALID_ENDS_AT, expiryPolicy: "delete", displayName: "Festival name" } },
        deps,
      );

      const member = await deps.groupRepo.getMember(result.groupId, "u1");
      expect(member?.displayName).toBe("Festival name");
    });
  });

  describe("features resolution", () => {
    it("returns implicit free features for a family-less caller", async () => {
      const deps = buildDeps();

      const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

      expect(result.features).toEqual(getFeatures("free"));
    });

    it("resolves features from the caller's family entitlements when they have a family", async () => {
      const deps = buildDeps();
      deps.userRepo.seed("u1", { familyId: "fam_existing0000000000", role: "parent", displayName: "Eric" });
      deps.entitlementsRepo.seed("fam_existing0000000000", {
        subscriptionStatus: "active",
        updatedAt: "2026-07-01T00:00:00Z",
      });

      const result = await createGroup(
        { uid: "u1", body: { name: "Crew", endsAt: VALID_ENDS_AT, expiryPolicy: "delete" } },
        deps,
      );

      expect(result.features).toEqual(getFeatures("active"));
    });

    it("throws INTERNAL_ERROR when the caller's family has no Entitlements record", async () => {
      const deps = buildDeps();
      deps.userRepo.seed("u1", { familyId: "fam_no_entitlements00", role: "parent", displayName: "Eric" });
      // Deliberately NOT seeding entitlementsRepo for fam_no_entitlements00.

      await expectAppError(
        createGroup({ uid: "u1", body: { name: "Crew", endsAt: VALID_ENDS_AT, expiryPolicy: "delete" } }, deps),
        "INTERNAL_ERROR",
      );
    });
  });

  describe("validation (001 §12.1)", () => {
    it("accepts expiryPolicy grace", async () => {
      const deps = buildDeps();

      const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, expiryPolicy: "grace" } }, deps);

      expect(result.expiryPolicy).toBe("grace");
    });

    it("accepts expiryPolicy archive", async () => {
      const deps = buildDeps();

      const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, expiryPolicy: "archive" } }, deps);

      expect(result.expiryPolicy).toBe("archive");
    });

    it('throws VALIDATION_FAILED with details.fields: ["name"] for an empty name', async () => {
      const deps = buildDeps();

      await expectAppError(
        createGroup({ uid: "u1", body: { ...VALID_BODY, name: "" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["name"] },
      );
    });

    it("throws VALIDATION_FAILED for a name over 50 chars", async () => {
      const deps = buildDeps();

      await expectAppError(
        createGroup({ uid: "u1", body: { ...VALID_BODY, name: "x".repeat(51) } }, deps),
        "VALIDATION_FAILED",
        { fields: ["name"] },
      );
    });

    it("throws VALIDATION_FAILED for an invalid expiryPolicy", async () => {
      const deps = buildDeps();

      await expectAppError(
        createGroup({ uid: "u1", body: { ...VALID_BODY, expiryPolicy: "bogus" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["expiryPolicy"] },
      );
    });

    it("throws VALIDATION_FAILED for a non-object body", async () => {
      const deps = buildDeps();

      await expectAppError(createGroup({ uid: "u1", body: "nope" }, deps), "VALIDATION_FAILED", {
        fields: ["(root)"],
      });
    });

    it("throws VALIDATION_FAILED when endsAt is less than now + 1h", async () => {
      const deps = buildDeps();
      const tooSoon = new Date(NOW.getTime() + 59 * 60 * 1000).toISOString();

      await expectAppError(
        createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: tooSoon } }, deps),
        "VALIDATION_FAILED",
        { fields: ["endsAt"] },
      );
    });

    it("accepts endsAt exactly at now + 1h (boundary)", async () => {
      const deps = buildDeps();
      const exactly1h = new Date(NOW.getTime() + 60 * 60 * 1000).toISOString();

      const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: exactly1h } }, deps);

      expect(result.endsAt).toBe(exactly1h);
    });

    it("accepts any future dated endsAt when maxGroupDurationDays is null (shipped free plan, 001 §9)", async () => {
      const deps = buildDeps();
      const tenYears = new Date(NOW.getTime() + 3650 * 24 * 60 * 60 * 1000).toISOString();

      const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: tenYears } }, deps);

      expect(result.endsAt).toBe(tenYears);
    });

    describe("with a numeric maxGroupDurationDays (30)", () => {
      useLimitOverride({ maxGroupDurationDays: 30 });

      it('throws LIMIT_EXCEEDED with details.limit: "maxGroupDurationDays" when endsAt exceeds the horizon', async () => {
        const deps = buildDeps();
        const tooFar = new Date(NOW.getTime() + 31 * 24 * 60 * 60 * 1000).toISOString();

        await expectAppError(
          createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: tooFar } }, deps),
          "LIMIT_EXCEEDED",
          { limit: "maxGroupDurationDays" },
        );
      });

      it("accepts endsAt exactly at now + maxGroupDurationDays (boundary)", async () => {
        const deps = buildDeps();
        const exactlyAtHorizon = new Date(NOW.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();

        const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: exactlyAtHorizon } }, deps);

        expect(result.endsAt).toBe(exactlyAtHorizon);
      });

      it("never applies the horizon to endsAt: null (005 §2.5)", async () => {
        const deps = buildDeps();

        const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: null } }, deps);

        expect(result.endsAt).toBeNull();
      });
    });
  });

  describe("groups without an end date (005 §2.5, 001 §12.1)", () => {
    it("creates an active group with endsAt null and writes NO GroupExpiry row", async () => {
      const deps = buildDeps();

      const result = await createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: null } }, deps);

      expect(result.endsAt).toBeNull();
      expect(result.state).toBe("active");
      expect(result.code).toBe("00000001");
      expect(deps.groupExpiryRepo.size()).toBe(0);
      const meta = await deps.groupRepo.getGroupMeta(result.groupId);
      expect(meta?.endsAt).toBeNull();
    });

    it('rejects a body with the endsAt KEY MISSING: VALIDATION_FAILED, details.fields ["endsAt"]', async () => {
      const deps = buildDeps();
      const { endsAt: _omitted, ...withoutEndsAt } = VALID_BODY;

      await expectAppError(createGroup({ uid: "u1", body: withoutEndsAt }, deps), "VALIDATION_FAILED", {
        fields: ["endsAt"],
      });
      expect(deps.groupExpiryRepo.size()).toBe(0);
    });

    it("rejects an explicit undefined endsAt the same way (key effectively missing)", async () => {
      const deps = buildDeps();

      await expectAppError(
        createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: undefined } }, deps),
        "VALIDATION_FAILED",
        { fields: ["endsAt"] },
      );
    });

    it("rejects a non-datetime, non-null endsAt", async () => {
      const deps = buildDeps();

      await expectAppError(
        createGroup({ uid: "u1", body: { ...VALID_BODY, endsAt: "tomorrow" } }, deps),
        "VALIDATION_FAILED",
        { fields: ["endsAt"] },
      );
    });
  });

  describe("maxOwnedGroups capacity over ACTIVE owned groups only (005 §4, 001 §12.1)", () => {
    async function seedGroup(
      deps: ReturnType<typeof buildDeps>,
      id: string,
      role: "owner" | "member",
      overrides: Partial<GroupMeta> = {},
    ) {
      await deps.groupRepo.createGroupMeta({
        groupId: id,
        name: `Seeded ${id}`,
        ownerUserId: role === "owner" ? "u1" : "someone-else",
        createdAt: "2026-07-01T00:00:00Z",
        endsAt: VALID_ENDS_AT,
        expiryPolicy: "delete",
        code: `C${id}`.slice(0, 8),
        ...overrides,
      });
      await deps.userRepo.addGroupMembership("u1", { groupId: id, role, joinedAt: "2026-07-01T00:00:00Z" });
    }

    it('throws LIMIT_EXCEEDED {limit:"maxOwnedGroups"} when 5 active owned groups exist', async () => {
      const deps = buildDeps();
      for (let i = 0; i < 5; i += 1) await seedGroup(deps, `grp_own${i}`, "owner");

      await expectAppError(createGroup({ uid: "u1", body: VALID_BODY }, deps), "LIMIT_EXCEEDED", {
        limit: "maxOwnedGroups",
      });
    });

    it("allows a create with 4 active owned groups plus 5 joined (joined never count against owned)", async () => {
      const deps = buildDeps();
      for (let i = 0; i < 4; i += 1) await seedGroup(deps, `grp_own${i}`, "owner");
      for (let i = 0; i < 5; i += 1) await seedGroup(deps, `grp_mem${i}`, "member");

      const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

      expect(result.state).toBe("active");
    });

    it("counts a no-end-date owned group as active", async () => {
      const deps = buildDeps();
      for (let i = 0; i < 5; i += 1) await seedGroup(deps, `grp_own${i}`, "owner", { endsAt: null });

      await expectAppError(createGroup({ uid: "u1", body: VALID_BODY }, deps), "LIMIT_EXCEEDED", {
        limit: "maxOwnedGroups",
      });
    });

    it("does not count an archived or ended owned group: 5 owned of which 1 archived and 1 ended -> allowed", async () => {
      const deps = buildDeps();
      for (let i = 0; i < 3; i += 1) await seedGroup(deps, `grp_own${i}`, "owner");
      await seedGroup(deps, "grp_arch", "owner", { endsAt: "2026-07-01T00:00:00Z", expiryPolicy: "archive" });
      await seedGroup(deps, "grp_ended", "owner", { endsAt: "2026-07-20T00:00:00Z", expiryPolicy: "grace" });

      const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

      expect(result.state).toBe("active");
    });

    it("still refuses with 5 active owned even when ended/archived ones also exist", async () => {
      const deps = buildDeps();
      for (let i = 0; i < 5; i += 1) await seedGroup(deps, `grp_own${i}`, "owner");
      await seedGroup(deps, "grp_arch", "owner", { endsAt: "2026-07-01T00:00:00Z", expiryPolicy: "archive" });

      await expectAppError(createGroup({ uid: "u1", body: VALID_BODY }, deps), "LIMIT_EXCEEDED", {
        limit: "maxOwnedGroups",
      });
    });

    it("excludes expired memberships from the count", async () => {
      const deps = buildDeps();
      for (let i = 0; i < 5; i += 1) {
        await seedGroup(deps, `grp_expired${i}`, "owner", {
          createdAt: "2026-01-01T00:00:00Z",
          endsAt: "2026-01-02T00:00:00Z", // long past NOW, delete policy
        });
      }

      const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

      expect(result.state).toBe("active");
    });

    it("tolerates an orphaned reverse-index row (group meta missing — self-healing skip)", async () => {
      const deps = buildDeps();
      await deps.userRepo.addGroupMembership("u1", { groupId: "grp_gone00000000000000", role: "owner", joinedAt: NOW.toISOString() });

      const result = await createGroup({ uid: "u1", body: VALID_BODY }, deps);

      expect(result.state).toBe("active");
    });
  });

  it("normalizes displayName at write time before storing (strips a right-to-left override, 001 §1.4/B29)", async () => {
    const deps = buildDeps();

    const result = await createGroup(
      { uid: "u1", body: { ...VALID_BODY, displayName: "Eric\u202EcirE" } },
      deps,
    );

    expect(result.role).toBe("owner");
    const members = await deps.groupRepo.listMembers(result.groupId);
    expect(members[0]?.displayName).toBe("EriccirE");
  });

});
