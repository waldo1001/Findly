import { describe, expect, it } from "vitest";
import { acceptInvite } from "../../../src/domain/family/acceptInvite";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryInviteRepo } from "../../fakes/inMemoryInviteRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { InviteRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const INVITE_CODE = "7F3K9QRZ";

function buildDeps() {
  const familyRepo = new InMemoryFamilyRepo();
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  return {
    inviteRepo: new InMemoryInviteRepo(),
    familyRepo,
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo,
    clock: new FixedClock(new Date("2026-07-19T09:00:00Z")),
  };
}

async function seedFamily(deps: ReturnType<typeof buildDeps>) {
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
  deps.entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
}

function baseInvite(overrides: Partial<InviteRecord> = {}): InviteRecord {
  return {
    inviteCode: INVITE_CODE,
    familyId: FAMILY_ID,
    role: "member",
    createdBy: "u1",
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-22T08:00:00Z",
    ...overrides,
  };
}

describe("domain/family/acceptInvite", () => {
  it("joins the family, writing Families member + Users profile rows", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite());

    const result = await acceptInvite(
      { uid: "u2", familyId: null, body: { inviteCode: "7f3k-9qrz", displayName: "Noor" } },
      deps,
    );

    expect(result).toEqual({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      role: "member",
      features: getFeatures("free"),
    });

    const members = await deps.familyRepo.listMembers(FAMILY_ID);
    expect(members).toContainEqual({
      userId: "u2",
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-19T09:00:00.000Z",
    });
    const profile = await deps.userRepo.getProfile("u2");
    expect(profile).toEqual({ familyId: FAMILY_ID, role: "member", displayName: "Noor" });
  });

  it("normalizes the invite code (case-insensitive, hyphens ignored) before lookup", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite());

    const result = await acceptInvite(
      { uid: "u2", familyId: null, body: { inviteCode: "7f3k-9qrz", displayName: "Noor" } },
      deps,
    );

    expect(result.role).toBe("member");
  });

  it("throws FAMILY_ALREADY_MEMBER when the caller already belongs to a family", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite());

    await expectAppError(
      acceptInvite(
        { uid: "u2", familyId: "fam_other0000000000000", body: { inviteCode: INVITE_CODE, displayName: "Noor" } },
        deps,
      ),
      "FAMILY_ALREADY_MEMBER",
    );
  });

  it("throws INVITE_INVALID for an unknown invite code", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: "NOSUCHCD", displayName: "Noor" } }, deps),
      "INVITE_INVALID",
    );
  });

  it("throws INVITE_EXPIRED when now is past expiresAt", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite({ expiresAt: "2026-07-19T08:59:59Z" }));

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      "INVITE_EXPIRED",
    );
  });

  it("throws INVITE_EXPIRED when now exactly equals expiresAt (inclusive boundary)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite({ expiresAt: "2026-07-19T09:00:00.000Z" }));

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      "INVITE_EXPIRED",
    );
  });

  it("accepts one millisecond before expiresAt (not yet expired)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite({ expiresAt: "2026-07-19T09:00:00.001Z" }));

    const result = await acceptInvite(
      { uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } },
      deps,
    );

    expect(result.role).toBe("member");
  });

  it("throws INVITE_ALREADY_USED when the code was already consumed", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite({ usedBy: "someone-else", usedAt: "2026-07-19T08:30:00Z" }));

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      "INVITE_ALREADY_USED",
    );
  });

  it("is race-safe: exactly one of two concurrent accepts on the same code wins", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite());

    const [resultA, resultB] = await Promise.allSettled([
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      acceptInvite({ uid: "u3", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Alex" } }, deps),
    ]);

    const outcomes = [resultA, resultB];
    const fulfilled = outcomes.filter((o) => o.status === "fulfilled");
    const rejected = outcomes.filter((o) => o.status === "rejected");
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    if (rejected[0]?.status === "rejected") {
      expect(rejected[0].reason.code).toBe("INVITE_ALREADY_USED");
    }

    const members = await deps.familyRepo.listMembers(FAMILY_ID);
    // Only the winner (creator "u1" + exactly one of u2/u3) ends up in the roster.
    expect(members).toHaveLength(2);
  });

  it("fails closed with INVITE_INVALID when the invite references a family with no meta record (deleted family, 008 §5.3/001 §3.4)", async () => {
    const deps = buildDeps();
    // Entitlements ARE seeded (isolating this check from the separate entitlements-missing
    // one below) but familyRepo.createFamily was deliberately never called for FAMILY_ID —
    // getFamilyMeta returns null even though the invite points at this familyId. This is
    // exactly the "straggler invite row survives a partially-failed family deletion"
    // scenario (002 §2.1): acceptance MUST behave identically to an unknown code, never
    // resurrecting a deleted family and never leaking that the family once existed.
    deps.entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
    await deps.inviteRepo.createInvite(baseInvite());

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      "INVITE_INVALID",
    );
  });

  it("does not consume the invite code when failing closed on a deleted family", async () => {
    const deps = buildDeps();
    deps.entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
    await deps.inviteRepo.createInvite(baseInvite());

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      "INVITE_INVALID",
    );

    const stillUnconsumed = await deps.inviteRepo.getInvite(INVITE_CODE);
    expect(stillUnconsumed?.usedBy).toBeUndefined();
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
    const inviteRepo = new InMemoryInviteRepo();
    await inviteRepo.createInvite(baseInvite());
    const deps = {
      inviteRepo,
      familyRepo,
      userRepo: new InMemoryUserRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
      clock: new FixedClock(new Date("2026-07-19T09:00:00Z")),
    };

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "Noor" } }, deps),
      "INTERNAL_ERROR",
    );
  });

  it('throws VALIDATION_FAILED with details.fields: ["displayName"] for an empty displayName', async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.inviteRepo.createInvite(baseInvite());

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: INVITE_CODE, displayName: "" } }, deps),
      "VALIDATION_FAILED",
      { fields: ["displayName"] },
    );
  });

  it('throws VALIDATION_FAILED with details.fields: ["inviteCode"] for an empty inviteCode', async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      acceptInvite({ uid: "u2", familyId: null, body: { inviteCode: "", displayName: "Noor" } }, deps),
      "VALIDATION_FAILED",
      { fields: ["inviteCode"] },
    );
  });
});
