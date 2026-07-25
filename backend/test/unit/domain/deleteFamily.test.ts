// specs/001 §13.3 `DELETE /api/v1/families/me` (parent). Pure domain logic: role/family
// checks live here; the actual teardown is delegated to the shared
// src/domain/family/familyDeletion.ts function (B18 reuses that same function for its
// last-parent/sole-member cascade).

import { describe, expect, it } from "vitest";
import { deleteFamily } from "../../../src/domain/family/deleteFamily";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryInviteRepo } from "../../fakes/inMemoryInviteRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryLocateRequestRepo } from "../../fakes/inMemoryLocateRequestRepo";
import { InMemoryHistoryStore } from "../../fakes/inMemoryHistoryStore";
import { InMemoryGeofenceConfigRepo } from "../../fakes/inMemoryGeofenceConfigRepo";
import { expectAppError } from "../../support/expectAppError";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const CALLER = "u1";
const OTHER_MEMBER = "u2";

function buildDeps() {
  return {
    familyRepo: new InMemoryFamilyRepo(),
    userRepo: new InMemoryUserRepo(),
    inviteRepo: new InMemoryInviteRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    usageRepo: new InMemoryUsageRepo(),
    locateRequestRepo: new InMemoryLocateRequestRepo(),
    historyStore: new InMemoryHistoryStore(),
    geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
  };
}

async function seedFamily(deps: ReturnType<typeof buildDeps>) {
  await deps.familyRepo.createFamily({ familyId: FAMILY_ID, familyName: "Wauters", createdBy: CALLER, createdAt: "2026-07-19T08:00:00Z" });
  await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.familyRepo.addMember(FAMILY_ID, { userId: OTHER_MEMBER, role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
  await deps.userRepo.createProfile(OTHER_MEMBER, { familyId: FAMILY_ID, role: "member", displayName: "Noor" });
  await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");
}

describe("domain/family/deleteFamily", () => {
  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();

    await expectAppError(deleteFamily({ uid: CALLER, familyId: null, role: null }, deps), "FAMILY_NOT_FOUND");
  });

  it("throws AUTH_FORBIDDEN when the caller is not a parent", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      deleteFamily({ uid: OTHER_MEMBER, familyId: FAMILY_ID, role: "member" }, deps),
      "AUTH_FORBIDDEN",
    );
  });

  it("returns void (bare 204, specs/001 §13.3) and tears down the family for a parent caller", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    const result = await deleteFamily({ uid: CALLER, familyId: FAMILY_ID, role: "parent" }, deps);

    expect(result).toBeUndefined();
    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
    expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: null, role: null, displayName: "Eric" });
    expect(await deps.userRepo.getProfile(OTHER_MEMBER)).toEqual({ familyId: null, role: null, displayName: "Noor" });
  });

  it("is re-callable until clean: a crash after meta deletion but before the caller's flip converges on retry (specs/008 §5.5)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // Simulate everything up through step 5 having already run in a prior (crashed) call —
    // the caller's own Users profile is the only thing still pointing at the family, which
    // is exactly what lets the endpoint's own role check (001 §1.6) admit the retry.
    await deps.userRepo.updateProfile(OTHER_MEMBER, { familyId: null, role: null });
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_MEMBER);
    await deps.familyRepo.removeMember(FAMILY_ID, CALLER);
    await deps.entitlementsRepo.delete(FAMILY_ID);
    await deps.usageRepo.deletePartition(FAMILY_ID);
    await deps.locateRequestRepo.deletePartition(FAMILY_ID);
    await deps.historyStore.deleteFamilyPrefix(FAMILY_ID);
    await deps.geofenceConfigRepo.deleteConfig(FAMILY_ID);
    await deps.familyRepo.deleteFamilyMeta(FAMILY_ID);

    await deleteFamily({ uid: CALLER, familyId: FAMILY_ID, role: "parent" }, deps);

    expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: null, role: null, displayName: "Eric" });
  });
});
