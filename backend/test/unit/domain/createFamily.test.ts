import { describe, expect, it } from "vitest";
import { createFamily } from "../../../src/domain/family/createFamily";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { SeqIdGenerator } from "../../fakes/seqIdGenerator";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";

function buildDeps() {
  return {
    familyRepo: new InMemoryFamilyRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    idGenerator: new SeqIdGenerator(),
    clock: new FixedClock(new Date("2026-07-19T09:00:00Z")),
  };
}

describe("domain/family/createFamily", () => {
  it("creates the family with the given name; creator becomes role parent", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric" } },
      deps,
    );

    expect(result.familyName).toBe("Wauters");
    expect(result.member).toEqual({ userId: "u1", role: "parent", displayName: "Eric" });
  });

  it("persists the creator as a parent member row on the family (via the repo fake)", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric" } },
      deps,
    );

    const members = await deps.familyRepo.listMembers(result.familyId);
    expect(members).toEqual([
      { userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T09:00:00.000Z" },
    ]);
  });

  it("generates fam_ + 20 chars [A-Za-z0-9] via the IdGenerator port", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric" } },
      deps,
    );

    expect(result.familyId).toMatch(/^fam_[A-Za-z0-9]{20}$/);
  });

  it("writes the Users profile row (uid -> familyId, role) via the repo fake", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric" } },
      deps,
    );

    const profile = await deps.userRepo.getProfile("u1");
    expect(profile).toEqual({ familyId: result.familyId, role: "parent", displayName: "Eric" });
  });

  it("creates Entitlements with subscriptionStatus: free", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric" } },
      deps,
    );

    const entitlements = await deps.entitlementsRepo.get(result.familyId);
    expect(entitlements?.subscriptionStatus).toBe("free");
  });

  it("returns features === derivation from PLAN_MATRIX.free", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric" } },
      deps,
    );

    expect(result.features).toEqual(getFeatures("free"));
  });

  it("throws FAMILY_ALREADY_MEMBER when the caller already has a family", async () => {
    const deps = buildDeps();

    await expectAppError(
      createFamily(
        { uid: "u1", familyId: "fam_existing00000000000", body: { familyName: "X", displayName: "Y" } },
        deps,
      ),
      "FAMILY_ALREADY_MEMBER",
    );
  });

  it("throws VALIDATION_FAILED with details.fields: [\"familyName\"] for an empty familyName", async () => {
    const deps = buildDeps();

    await expectAppError(
      createFamily({ uid: "u1", familyId: null, body: { familyName: "", displayName: "Eric" } }, deps),
      "VALIDATION_FAILED",
      { fields: ["familyName"] },
    );
  });

  it("throws VALIDATION_FAILED for a familyName over 50 chars", async () => {
    const deps = buildDeps();

    await expectAppError(
      createFamily(
        { uid: "u1", familyId: null, body: { familyName: "x".repeat(51), displayName: "Eric" } },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["familyName"] },
    );
  });

  it("throws VALIDATION_FAILED with details.fields: [\"displayName\"] for a missing displayName", async () => {
    const deps = buildDeps();

    await expectAppError(
      createFamily({ uid: "u1", familyId: null, body: { familyName: "Wauters" } }, deps),
      "VALIDATION_FAILED",
      { fields: ["displayName"] },
    );
  });

  it("throws VALIDATION_FAILED with details.fields: [\"(root)\"] for a non-object body", async () => {
    const deps = buildDeps();

    await expectAppError(
      createFamily({ uid: "u1", familyId: null, body: "not-an-object" }, deps),
      "VALIDATION_FAILED",
      { fields: ["(root)"] },
    );
  });

  it("normalizes displayName at write time before storing (strips a right-to-left override, 001 §1.4/B29)", async () => {
    const deps = buildDeps();

    const result = await createFamily(
      { uid: "u1", familyId: null, body: { familyName: "Wauters", displayName: "Eric‮cirE" } },
      deps,
    );

    expect(result.member.displayName).toBe("EriccirE");
    const profile = await deps.userRepo.getProfile("u1");
    expect(profile?.displayName).toBe("EriccirE");
  });

});
