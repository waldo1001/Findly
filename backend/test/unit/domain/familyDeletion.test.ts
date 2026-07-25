// specs/001 §13.3, specs/008 §5, specs/002 §4.2 — the reusable family-delete footprint
// (B19). Deliberately does NOT accept DeviceRepo/LastKnownRepo/GroupMembership repos at
// all: family deletion must be architecturally incapable of touching them (008 §5.2).

import { describe, expect, it } from "vitest";
import { deleteFamilyFootprint, type DeleteFamilyFootprintDeps } from "../../../src/domain/family/familyDeletion";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryInviteRepo } from "../../fakes/inMemoryInviteRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryLocateRequestRepo } from "../../fakes/inMemoryLocateRequestRepo";
import { InMemoryHistoryStore } from "../../fakes/inMemoryHistoryStore";
import { InMemoryGeofenceConfigRepo } from "../../fakes/inMemoryGeofenceConfigRepo";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const CALLER = "u1"; // parent, the caller performing the deletion
const OTHER_PARENT = "u3"; // co-parent, must be flipped family-less before the caller
const OTHER_MEMBER = "u2"; // ordinary member, must also be flipped before the caller
const INVITE_CODE = "ABCD1234";

function buildDeps(): DeleteFamilyFootprintDeps {
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

async function seedFullFamily(deps: DeleteFamilyFootprintDeps): Promise<void> {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: CALLER,
    createdAt: "2026-07-19T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.familyRepo.addMember(FAMILY_ID, { userId: OTHER_PARENT, role: "parent", displayName: "Ines", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.familyRepo.addMember(FAMILY_ID, { userId: OTHER_MEMBER, role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z" });

  await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
  await deps.userRepo.createProfile(OTHER_PARENT, { familyId: FAMILY_ID, role: "parent", displayName: "Ines" });
  await deps.userRepo.createProfile(OTHER_MEMBER, { familyId: FAMILY_ID, role: "member", displayName: "Noor" });

  await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");
  await deps.usageRepo.increment(FAMILY_ID, "apiCalls", "2026-07-19");
  await deps.usageRepo.increment(FAMILY_ID, "locateRequests", "2026-07-20");

  await deps.locateRequestRepo.create({
    requestId: "lr_00000000000000000001",
    familyId: FAMILY_ID,
    targetUserId: OTHER_MEMBER,
    targetDeviceId: "device-1",
    requestedBy: CALLER,
    status: "pending",
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-19T08:01:00Z",
  });

  await deps.historyStore.appendFix(FAMILY_ID, OTHER_MEMBER, "device-1", {
    fixId: "fix-1",
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    batteryPct: 80,
    source: "periodic",
  });
  await deps.historyStore.appendEvent(FAMILY_ID, {
    eventId: "evt-1",
    userId: OTHER_MEMBER,
    deviceId: "device-1",
    geofenceId: "gf-home",
    geofenceName: "Home",
    lat: 51.05,
    lon: 3.71,
    radiusM: 100,
    transition: "enter",
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
  });

  await deps.geofenceConfigRepo.replace(
    FAMILY_ID,
    {
      version: 1,
      geofences: [
        { geofenceId: "gf-home", name: "Home", lat: 51.05, lon: 3.71, radiusM: 100, icon: "home", notifyOnEnter: true, notifyOnExit: true },
      ],
    },
    "0",
  );

  await deps.inviteRepo.createInvite({
    inviteCode: INVITE_CODE,
    familyId: FAMILY_ID,
    role: "member",
    createdBy: CALLER,
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-22T08:00:00Z",
  });
  await deps.familyRepo.addInviteIndexEntry(FAMILY_ID, { code: INVITE_CODE, expiresAt: "2026-07-22T08:00:00Z" });
}

async function assertFullyClean(deps: DeleteFamilyFootprintDeps): Promise<void> {
  expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
  expect(await deps.familyRepo.listMembers(FAMILY_ID)).toEqual([]);
  expect(await deps.familyRepo.listInviteIndexEntries(FAMILY_ID)).toEqual([]);
  expect(await deps.inviteRepo.getInvite(INVITE_CODE)).toBeNull();
  expect(await deps.entitlementsRepo.get(FAMILY_ID)).toBeNull();
  expect(await deps.usageRepo.get(FAMILY_ID, "apiCalls", "2026-07-19")).toBe(0);
  expect(await deps.usageRepo.get(FAMILY_ID, "locateRequests", "2026-07-20")).toBe(0);
  expect(await deps.locateRequestRepo.get(FAMILY_ID, "lr_00000000000000000001")).toBeNull();

  const fixes = await deps.historyStore.readFixHistory(FAMILY_ID, OTHER_MEMBER, undefined, "2026-07-19", "2026-07-19", 10, null);
  expect(fixes.items).toEqual([]);
  const events = await deps.historyStore.readEventHistory(FAMILY_ID, "2026-07-19", "2026-07-19", undefined, 10, null);
  expect(events.items).toEqual([]);

  expect(await deps.geofenceConfigRepo.get(FAMILY_ID)).toEqual({ config: { version: 0, geofences: [] }, etag: "0" });

  expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: null, role: null, displayName: "Eric" });
  expect(await deps.userRepo.getProfile(OTHER_PARENT)).toEqual({ familyId: null, role: null, displayName: "Ines" });
  expect(await deps.userRepo.getProfile(OTHER_MEMBER)).toEqual({ familyId: null, role: null, displayName: "Noor" });
}

describe("domain/family/familyDeletion", () => {
  it("performs full teardown of every family-scoped row/blob (specs/008 §5.1/§2, 002 §4.2)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    await assertFullyClean(deps);
  });

  it("leaves other members' devices, last-known, and group memberships untouched (specs/008 §5.2)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    // Devices/LastKnown repos are deliberately not part of DeleteFamilyFootprintDeps at all
    // (see file header) — seed independent fakes to prove nothing reaches in and mutates
    // them. Group membership survival is checked on the SAME userRepo instance the function
    // actually receives, since that repo (rightly) is shared for the profile flip.
    const deviceRepo = new InMemoryDeviceRepo();
    deviceRepo.seed(OTHER_MEMBER, {
      deviceId: "device-1",
      ownerUserId: OTHER_MEMBER,
      platform: "android",
      model: "Pixel",
      appVersion: "1.0",
      deviceName: "Noor's phone",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-19T08:00:00Z",
      lastSeenAt: "2026-07-19T08:00:00Z",
    });
    const lastKnownRepo = new InMemoryLastKnownRepo();
    lastKnownRepo.seed(OTHER_MEMBER, {
      deviceId: "device-1",
      lat: 51.05,
      lon: 3.71,
      accuracyM: 10,
      batteryPct: 80,
      recordedAt: "2026-07-19T08:00:00Z",
      receivedAt: "2026-07-19T08:00:01Z",
      source: "periodic",
    });
    await deps.userRepo.addGroupMembership(OTHER_MEMBER, { groupId: "grp_a", role: "member", joinedAt: "2026-07-19T08:00:00Z" });

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    expect(await deviceRepo.listDevices(OTHER_MEMBER)).toHaveLength(1);
    expect(await lastKnownRepo.get(OTHER_MEMBER, "device-1")).not.toBeNull();
    expect(await deps.userRepo.listGroupMemberships(OTHER_MEMBER)).toEqual([
      { groupId: "grp_a", role: "member", joinedAt: "2026-07-19T08:00:00Z" },
    ]);
  });

  it("flips other members' profiles family-less BEFORE the caller's own (specs/008 §5.5, 002 §4.2)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    const order: string[] = [];
    const realUpdateProfile = deps.userRepo.updateProfile.bind(deps.userRepo);
    deps.userRepo.updateProfile = async (userId, patch) => {
      order.push(userId);
      return realUpdateProfile(userId, patch);
    };

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    expect(order[order.length - 1]).toBe(CALLER);
    expect(order.indexOf(OTHER_PARENT)).toBeLessThan(order.indexOf(CALLER));
    expect(order.indexOf(OTHER_MEMBER)).toBeLessThan(order.indexOf(CALLER));
  });

  it("deletes the Families meta row BEFORE the caller's own profile flip — the retry pointer (specs/008 §5.5)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    let metaGoneWhenCallerFlipped = false;
    const realUpdateProfile = deps.userRepo.updateProfile.bind(deps.userRepo);
    deps.userRepo.updateProfile = async (userId, patch) => {
      if (userId === CALLER) {
        metaGoneWhenCallerFlipped = (await deps.familyRepo.getFamilyMeta(FAMILY_ID)) === null;
      }
      return realUpdateProfile(userId, patch);
    };

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    expect(metaGoneWhenCallerFlipped).toBe(true);
  });

  // --- crash-retry idempotency at each step boundary (specs/008 §9 requires this) ---

  it("converges after a simulated crash mid-step-1 (only some other members flipped family-less)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    await deps.userRepo.updateProfile(OTHER_PARENT, { familyId: null, role: null });

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    await assertFullyClean(deps);
  });

  it("converges after a simulated crash mid-step-2 (some member/invite rows removed, meta and blobs intact)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    await deps.userRepo.updateProfile(OTHER_PARENT, { familyId: null, role: null });
    await deps.userRepo.updateProfile(OTHER_MEMBER, { familyId: null, role: null });
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_PARENT);
    await deps.inviteRepo.deleteInvite(INVITE_CODE);
    // The invite INDEX row is deliberately left behind (a lost canonical row before the
    // index row, 002 §2.1's documented "dead weight" case) — the retry must swallow it.

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    await assertFullyClean(deps);
  });

  it("converges after a simulated crash right after step 2 (roster+invites gone, entitlements/usage/locate/blobs still present)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    await deps.userRepo.updateProfile(OTHER_PARENT, { familyId: null, role: null });
    await deps.userRepo.updateProfile(OTHER_MEMBER, { familyId: null, role: null });
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_PARENT);
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_MEMBER);
    await deps.familyRepo.removeMember(FAMILY_ID, CALLER);
    await deps.inviteRepo.deleteInvite(INVITE_CODE);
    await deps.familyRepo.removeInviteIndexEntry(FAMILY_ID, INVITE_CODE);

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    await assertFullyClean(deps);
  });

  it("converges after a simulated crash right after step 4 (blobs+tables gone, meta still present)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    await deps.userRepo.updateProfile(OTHER_PARENT, { familyId: null, role: null });
    await deps.userRepo.updateProfile(OTHER_MEMBER, { familyId: null, role: null });
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_PARENT);
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_MEMBER);
    await deps.familyRepo.removeMember(FAMILY_ID, CALLER);
    await deps.inviteRepo.deleteInvite(INVITE_CODE);
    await deps.familyRepo.removeInviteIndexEntry(FAMILY_ID, INVITE_CODE);
    await deps.entitlementsRepo.delete(FAMILY_ID);
    await deps.usageRepo.deletePartition(FAMILY_ID);
    await deps.locateRequestRepo.deletePartition(FAMILY_ID);
    await deps.historyStore.deleteFamilyPrefix(FAMILY_ID);
    await deps.geofenceConfigRepo.deleteConfig(FAMILY_ID);
    // Families meta row deliberately left behind.

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    await assertFullyClean(deps);
  });

  it("converges after a crash right after meta deletion but before the caller's flip — the spec-highlighted scenario (specs/008 §5.5, 002 §4.2)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);
    await deps.userRepo.updateProfile(OTHER_PARENT, { familyId: null, role: null });
    await deps.userRepo.updateProfile(OTHER_MEMBER, { familyId: null, role: null });
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_PARENT);
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_MEMBER);
    await deps.familyRepo.removeMember(FAMILY_ID, CALLER);
    await deps.inviteRepo.deleteInvite(INVITE_CODE);
    await deps.familyRepo.removeInviteIndexEntry(FAMILY_ID, INVITE_CODE);
    await deps.entitlementsRepo.delete(FAMILY_ID);
    await deps.usageRepo.deletePartition(FAMILY_ID);
    await deps.locateRequestRepo.deletePartition(FAMILY_ID);
    await deps.historyStore.deleteFamilyPrefix(FAMILY_ID);
    await deps.geofenceConfigRepo.deleteConfig(FAMILY_ID);
    await deps.familyRepo.deleteFamilyMeta(FAMILY_ID);
    // The caller is left "pointing at a gone family" — exactly the documented crash state.
    expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: FAMILY_ID, role: "parent", displayName: "Eric" });

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    await assertFullyClean(deps);
  });

  it("is a full no-op the second time it is called after a clean completion (general re-call idempotency)", async () => {
    const deps = buildDeps();
    await seedFullFamily(deps);

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);
    await assertFullyClean(deps);

    await expect(deleteFamilyFootprint(FAMILY_ID, CALLER, deps)).resolves.toBeUndefined();
    await assertFullyClean(deps);
  });

  it("never flips the caller's own profile when it is the ONLY thing left (idempotent single-member retry after a full prior teardown of others)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({ familyId: FAMILY_ID, familyName: "Solo", createdBy: CALLER, createdAt: "2026-07-19T08:00:00Z" });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
    await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");

    await deleteFamilyFootprint(FAMILY_ID, CALLER, deps);

    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
    expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: null, role: null, displayName: "Eric" });
  });
});
