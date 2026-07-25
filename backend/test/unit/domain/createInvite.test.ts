import { describe, expect, it } from "vitest";
import { createInvite } from "../../../src/domain/family/createInvite";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryInviteRepo } from "../../fakes/inMemoryInviteRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { SeqInviteCodeGenerator } from "../../fakes/seqInviteCodeGenerator";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { InviteCodeGenerator } from "../../../src/ports/support";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
  return {
    inviteRepo: new InMemoryInviteRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    entitlementsRepo,
    inviteCodeGenerator: new SeqInviteCodeGenerator(),
    clock: new FixedClock(new Date("2026-07-19T09:00:00Z")),
  };
}

describe("domain/family/createInvite", () => {
  it("creates a single-use invite with the requested role and a 72h expiry", async () => {
    const deps = buildDeps();

    const result = await createInvite(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member" } },
      deps,
    );

    expect(result.inviteCode).toBe("00000001");
    expect(result.role).toBe("member");
    expect(result.expiresAt).toBe("2026-07-22T09:00:00.000Z");
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("accepts role: parent for the invitee", async () => {
    const deps = buildDeps();

    const result = await createInvite(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "parent" } },
      deps,
    );

    expect(result.role).toBe("parent");
  });

  it("stores the invite record via the repo fake", async () => {
    const deps = buildDeps();

    const result = await createInvite(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member", emailHint: "kid@example.com" } },
      deps,
    );

    const stored = await deps.inviteRepo.getInvite(result.inviteCode);
    expect(stored).toEqual({
      inviteCode: "00000001",
      familyId: FAMILY_ID,
      role: "member",
      emailHint: "kid@example.com",
      createdBy: "u1",
      createdAt: "2026-07-19T09:00:00.000Z",
      expiresAt: "2026-07-22T09:00:00.000Z",
    });
  });

  it("canonicalizes the generated code (uppercase, no hyphen) before storing", async () => {
    const lowerHyphenGenerator: InviteCodeGenerator = { next: () => "7f3k-9qrz" };
    const deps = { ...buildDeps(), inviteCodeGenerator: lowerHyphenGenerator };

    const result = await createInvite(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member" } },
      deps,
    );

    expect(result.inviteCode).toBe("7F3K9QRZ");
    const stored = await deps.inviteRepo.getInvite("7F3K9QRZ");
    expect(stored?.inviteCode).toBe("7F3K9QRZ");
  });

  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();

    await expectAppError(
      createInvite({ uid: "u1", familyId: null, role: null, body: { role: "member" } }, deps),
      "FAMILY_NOT_FOUND",
    );
  });

  it("throws AUTH_FORBIDDEN when the caller is not a parent", async () => {
    const deps = buildDeps();

    await expectAppError(
      createInvite({ uid: "u1", familyId: FAMILY_ID, role: "member", body: { role: "member" } }, deps),
      "AUTH_FORBIDDEN",
    );
  });

  it('throws VALIDATION_FAILED with details.fields: ["role"] for an invalid role', async () => {
    const deps = buildDeps();

    await expectAppError(
      createInvite({ uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "admin" } }, deps),
      "VALIDATION_FAILED",
      { fields: ["role"] },
    );
  });

  it('throws VALIDATION_FAILED with details.fields: ["emailHint"] for an invalid email', async () => {
    const deps = buildDeps();

    await expectAppError(
      createInvite(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member", emailHint: "not-an-email" } },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["emailHint"] },
    );
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = {
      inviteRepo: new InMemoryInviteRepo(),
      familyRepo: new InMemoryFamilyRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
      inviteCodeGenerator: new SeqInviteCodeGenerator(),
      clock: new FixedClock(new Date("2026-07-19T09:00:00Z")),
    };

    await expectAppError(
      createInvite({ uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member" } }, deps),
      "INTERNAL_ERROR",
    );
  });

  it("writes a Families invite: index row after the canonical Invites row (002 §2.1, B19)", async () => {
    const deps = buildDeps();

    const result = await createInvite(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member" } },
      deps,
    );

    const indexEntries = await deps.familyRepo.listInviteIndexEntries(FAMILY_ID);
    expect(indexEntries).toEqual([{ code: result.inviteCode, expiresAt: result.expiresAt }]);
  });

  it("canonicalizes the index row's code the same way as the canonical invite row", async () => {
    const lowerHyphenGenerator: InviteCodeGenerator = { next: () => "7f3k-9qrz" };
    const deps = { ...buildDeps(), inviteCodeGenerator: lowerHyphenGenerator };

    await createInvite({ uid: "u1", familyId: FAMILY_ID, role: "parent", body: { role: "member" } }, deps);

    const indexEntries = await deps.familyRepo.listInviteIndexEntries(FAMILY_ID);
    expect(indexEntries).toEqual([{ code: "7F3K9QRZ", expiresAt: "2026-07-22T09:00:00.000Z" }]);
  });
});
