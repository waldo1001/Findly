import { describe, expect, it } from "vitest";
import { updateMember } from "../../../src/domain/family/updateMember";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { expectAppError } from "../../support/expectAppError";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
  return {
    familyRepo: new InMemoryFamilyRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo,
  };
}

async function seedTwoParentFamily(deps: ReturnType<typeof buildDeps>) {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: "u1",
    createdAt: "2026-07-19T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: "u1",
    role: "parent",
    displayName: "Eric",
    joinedAt: "2026-07-19T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: "u2",
    role: "parent",
    displayName: "Noor",
    joinedAt: "2026-07-19T08:30:00Z",
  });
  await deps.userRepo.createProfile("u1", { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
  await deps.userRepo.createProfile("u2", { familyId: FAMILY_ID, role: "parent", displayName: "Noor" });
}

async function seedParentAndMemberFamily(deps: ReturnType<typeof buildDeps>) {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: "u1",
    createdAt: "2026-07-19T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: "u1",
    role: "parent",
    displayName: "Eric",
    joinedAt: "2026-07-19T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: "u2",
    role: "member",
    displayName: "Noor",
    joinedAt: "2026-07-19T08:30:00Z",
  });
  await deps.userRepo.createProfile("u1", { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
  await deps.userRepo.createProfile("u2", { familyId: FAMILY_ID, role: "member", displayName: "Noor" });
}

describe("domain/family/updateMember", () => {
  it("patches role and displayName, writing both Families + Users rows", async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    const result = await updateMember(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        targetUserId: "u2",
        body: { role: "member", displayName: "Noor W." },
      },
      deps,
    );

    expect(result.member).toEqual({
      userId: "u2",
      role: "member",
      displayName: "Noor W.",
      joinedAt: "2026-07-19T08:30:00Z",
    });
    expect(result.features).toEqual(getFeatures("free"));

    const familyRow = (await deps.familyRepo.listMembers(FAMILY_ID)).find((m) => m.userId === "u2");
    expect(familyRow).toEqual(result.member);
    const profile = await deps.userRepo.getProfile("u2");
    expect(profile).toEqual({ familyId: FAMILY_ID, role: "member", displayName: "Noor W." });
  });

  it("allows patching only displayName", async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    const result = await updateMember(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: { displayName: "Noor W." } },
      deps,
    );

    expect(result.member.role).toBe("parent");
    expect(result.member.displayName).toBe("Noor W.");
  });

  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();

    await expectAppError(
      updateMember(
        { uid: "u1", familyId: null, role: null, targetUserId: "u2", body: { displayName: "X" } },
        deps,
      ),
      "FAMILY_NOT_FOUND",
    );
  });

  it("throws AUTH_FORBIDDEN when the caller is not a parent", async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    await expectAppError(
      updateMember(
        { uid: "u1", familyId: FAMILY_ID, role: "member", targetUserId: "u2", body: { displayName: "X" } },
        deps,
      ),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws MEMBER_NOT_FOUND when the target userId is not in the family", async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    await expectAppError(
      updateMember(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "ghost", body: { displayName: "X" } },
        deps,
      ),
      "MEMBER_NOT_FOUND",
    );
  });

  it('throws VALIDATION_FAILED when neither role nor displayName is provided', async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    await expectAppError(
      updateMember({ uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: {} }, deps),
      "VALIDATION_FAILED",
    );
  });

  it('throws VALIDATION_FAILED with details.reason "lastParent" when demoting the only parent', async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: "u1",
      createdAt: "2026-07-19T08:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-19T08:00:00Z",
    });
    await deps.userRepo.createProfile("u1", { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });

    await expectAppError(
      updateMember(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u1", body: { role: "member" } },
        deps,
      ),
      "VALIDATION_FAILED",
      { reason: "lastParent" },
    );
  });

  it("allows demoting a parent when another parent remains", async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    const result = await updateMember(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: { role: "member" } },
      deps,
    );

    expect(result.member.role).toBe("member");
  });

  it("promotes a member to parent", async () => {
    const deps = buildDeps();
    await seedParentAndMemberFamily(deps);

    const result = await updateMember(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: { role: "parent" } },
      deps,
    );

    expect(result.member.role).toBe("parent");
  });

  it("does not run the last-parent check when patching only displayName for the sole parent", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: "u1",
      createdAt: "2026-07-19T08:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-19T08:00:00Z",
    });
    await deps.userRepo.createProfile("u1", { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });

    // Only field patched is displayName (role untouched) — must NOT trip the lastParent guard.
    const result = await updateMember(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u1", body: { displayName: "Eric W." } },
      deps,
    );

    expect(result.member).toEqual({
      userId: "u1",
      role: "parent",
      displayName: "Eric W.",
      joinedAt: "2026-07-19T08:00:00Z",
    });
  });

  it("does not run the last-parent check when re-confirming a non-parent member's role as member", async () => {
    const deps = buildDeps();
    await seedParentAndMemberFamily(deps);

    // patch.role === "member" but the target is already a member — not a demotion, must
    // NOT trip the lastParent guard even though the family has only one parent overall.
    const result = await updateMember(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: { role: "member" } },
      deps,
    );

    expect(result.member.role).toBe("member");
  });

  it('throws "lastParent" for the only parent demoting themselves even with a non-parent member present', async () => {
    const deps = buildDeps();
    await seedParentAndMemberFamily(deps);

    // Total member count is 2, but only 1 is a parent — the count MUST be parent-filtered.
    await expectAppError(
      updateMember(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u1", body: { role: "member" } },
        deps,
      ),
      "VALIDATION_FAILED",
      { reason: "lastParent" },
    );
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const familyRepo = new InMemoryFamilyRepo();
    await familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: "u1",
      createdAt: "2026-07-19T08:00:00Z",
    });
    await familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-19T08:00:00Z",
    });
    await familyRepo.addMember(FAMILY_ID, {
      userId: "u2",
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-19T08:30:00Z",
    });
    const userRepo = new InMemoryUserRepo();
    await userRepo.createProfile("u2", { familyId: FAMILY_ID, role: "member", displayName: "Noor" });
    const deps = {
      familyRepo,
      userRepo,
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
    };

    await expectAppError(
      updateMember(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: { displayName: "Noor W." } },
        deps,
      ),
      "INTERNAL_ERROR",
    );
  });

  it("normalizes displayName at write time before storing (strips a right-to-left override, 001 §1.4/B29)", async () => {
    const deps = buildDeps();
    await seedTwoParentFamily(deps);

    const result = await updateMember(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", targetUserId: "u2", body: { displayName: "Noor\u202EcirE" } },
      deps,
    );

    expect(result.member.displayName).toBe("NoorcirE");
  });

});
