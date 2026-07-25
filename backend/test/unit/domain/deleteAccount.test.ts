// specs/001 §13.2 `DELETE /api/v1/users/me`, specs/008 §4, specs/002 §4.2 — account
// deletion (B18). Reuses B19's familyDeletion.ts (cascade) and groupDeletion.ts (owned-group
// hard delete) — this suite exercises deleteAccount's OWN orchestration: devices-first/
// profile-last ordering, the last-parent/sole-member cascade trigger, owned-vs-joined group
// handling, locate-row erasure by either role, the events filtered rewrite (erases only the
// subject's lines), and crash-boundary re-call convergence (008 §9).

import { describe, expect, it } from "vitest";
import { deleteAccount, type DeleteAccountDeps } from "../../../src/domain/user/deleteAccount";
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
import { InMemoryIdempotencyRepo } from "../../fakes/inMemoryIdempotencyRepo";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupCodeRepo } from "../../fakes/inMemoryGroupCodeRepo";
import { InMemoryGroupLastKnownRepo } from "../../fakes/inMemoryGroupLastKnownRepo";
import { InMemoryGroupExpiryRepo } from "../../fakes/inMemoryGroupExpiryRepo";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const CALLER = "u1";
const OTHER_PARENT = "u3";
const OTHER_MEMBER = "u2";
const CALLER_DEVICE = "device-caller";
const OTHER_DEVICE = "device-other";
const OWNED_GROUP = "grp_owned0000000000";
const JOINED_GROUP = "grp_joined000000000";

function buildDeps(): DeleteAccountDeps {
  return {
    familyRepo: new InMemoryFamilyRepo(),
    userRepo: new InMemoryUserRepo(),
    inviteRepo: new InMemoryInviteRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    usageRepo: new InMemoryUsageRepo(),
    locateRequestRepo: new InMemoryLocateRequestRepo(),
    historyStore: new InMemoryHistoryStore(),
    geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
    deviceRepo: new InMemoryDeviceRepo(),
    lastKnownRepo: new InMemoryLastKnownRepo(),
    idempotencyRepo: new InMemoryIdempotencyRepo(),
    groupRepo: new InMemoryGroupRepo(),
    groupCodeRepo: new InMemoryGroupCodeRepo(),
    groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
    groupExpiryRepo: new InMemoryGroupExpiryRepo(),
  };
}

/** Seeds a 3-member family (CALLER, OTHER_PARENT, OTHER_MEMBER) plus every §2 "account
 * delete" row for CALLER, an owned group (CALLER owner, OTHER_MEMBER co-member), a joined
 * group (OTHER_MEMBER owner, CALLER member), and control data for OTHER_MEMBER that must
 * survive untouched. `callerRole` lets tests pick the cascade-vs-survive scenario. */
async function seedScenario(
  deps: DeleteAccountDeps,
  opts: { callerRole: "parent" | "member"; includeOtherParent: boolean },
): Promise<void> {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: CALLER,
    createdAt: "2026-07-19T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: CALLER,
    role: opts.callerRole,
    displayName: "Eric",
    joinedAt: "2026-07-19T08:00:00Z",
  });
  if (opts.includeOtherParent) {
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: OTHER_PARENT,
      role: "parent",
      displayName: "Ines",
      joinedAt: "2026-07-19T08:00:00Z",
    });
    await deps.userRepo.createProfile(OTHER_PARENT, { familyId: FAMILY_ID, role: "parent", displayName: "Ines" });
  }
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: OTHER_MEMBER,
    role: "member",
    displayName: "Noor",
    joinedAt: "2026-07-19T08:00:00Z",
  });
  await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: opts.callerRole, displayName: "Eric" });
  await deps.userRepo.createProfile(OTHER_MEMBER, { familyId: FAMILY_ID, role: "member", displayName: "Noor" });

  await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");
  await deps.usageRepo.increment(FAMILY_ID, "apiCalls", "2026-07-19");
  // CALLER's own uid-keyed Usage row, e.g. from a period spent family-less before joining
  // (002 §4.2 step 6, B18 follow-up) — a CURRENT family member can still hold these.
  await deps.usageRepo.increment(CALLER, "apiCalls", "2026-07-18");

  // Devices + LastKnown, both callers.
  await deps.deviceRepo.putDevice(CALLER, {
    deviceId: CALLER_DEVICE,
    ownerUserId: CALLER,
    platform: "android",
    model: "Pixel",
    appVersion: "1.0",
    deviceName: "Eric's phone",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-19T08:00:00Z",
    lastSeenAt: "2026-07-19T08:00:00Z",
  });
  await deps.deviceRepo.putDevice(OTHER_MEMBER, {
    deviceId: OTHER_DEVICE,
    ownerUserId: OTHER_MEMBER,
    platform: "ios",
    model: "iPhone",
    appVersion: "1.0",
    deviceName: "Noor's phone",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-19T08:00:00Z",
    lastSeenAt: "2026-07-19T08:00:00Z",
  });
  await deps.lastKnownRepo.upsertIfNewer(CALLER, {
    deviceId: CALLER_DEVICE,
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    batteryPct: 80,
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    source: "periodic",
  });
  await deps.lastKnownRepo.upsertIfNewer(OTHER_MEMBER, {
    deviceId: OTHER_DEVICE,
    lat: 51.06,
    lon: 3.72,
    accuracyM: 10,
    batteryPct: 90,
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    source: "periodic",
  });

  // IdempotencyMarkers: one per device.
  await deps.idempotencyRepo.tryInsertBatchMarker(CALLER_DEVICE, "batch-1", { receivedAt: "2026-07-19T08:00:00Z", fixCount: 1 });
  await deps.idempotencyRepo.tryInsertEventMarker(CALLER_DEVICE, "evt-marker-1", "2026-07-19T08:00:00Z");
  await deps.idempotencyRepo.tryInsertBatchMarker(OTHER_DEVICE, "batch-2", { receivedAt: "2026-07-19T08:00:00Z", fixCount: 1 });

  // LocateRequests naming CALLER in both roles.
  await deps.locateRequestRepo.create({
    requestId: "lr_00000000000000000001",
    familyId: FAMILY_ID,
    targetUserId: OTHER_MEMBER,
    targetDeviceId: OTHER_DEVICE,
    requestedBy: CALLER,
    status: "pending",
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-19T08:01:00Z",
  });
  await deps.locateRequestRepo.create({
    requestId: "lr_00000000000000000002",
    familyId: FAMILY_ID,
    targetUserId: CALLER,
    targetDeviceId: CALLER_DEVICE,
    requestedBy: OTHER_MEMBER,
    status: "pending",
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-19T08:01:00Z",
  });
  // Control row naming neither — must survive everything.
  await deps.locateRequestRepo.create({
    requestId: "lr_00000000000000000003",
    familyId: FAMILY_ID,
    targetUserId: OTHER_MEMBER,
    targetDeviceId: OTHER_DEVICE,
    requestedBy: OTHER_MEMBER,
    status: "pending",
    createdAt: "2026-07-19T08:00:00Z",
    expiresAt: "2026-07-19T08:01:00Z",
  });

  // History: both members have fixes; only CALLER's own prefix is erased.
  await deps.historyStore.appendFix(FAMILY_ID, CALLER, CALLER_DEVICE, {
    fixId: "fix-caller",
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    batteryPct: 80,
    source: "periodic",
  });
  await deps.historyStore.appendFix(FAMILY_ID, OTHER_MEMBER, OTHER_DEVICE, {
    fixId: "fix-other",
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    lat: 51.06,
    lon: 3.72,
    accuracyM: 10,
    batteryPct: 90,
    source: "periodic",
  });

  // Events: interleaved — only CALLER's line must be dropped by the filtered rewrite.
  await deps.historyStore.appendEvent(FAMILY_ID, {
    eventId: "evt-caller",
    userId: CALLER,
    deviceId: CALLER_DEVICE,
    geofenceId: "gf-home",
    geofenceName: "Home",
    lat: 51.05,
    lon: 3.71,
    radiusM: 100,
    transition: "enter",
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
  });
  await deps.historyStore.appendEvent(FAMILY_ID, {
    eventId: "evt-other",
    userId: OTHER_MEMBER,
    deviceId: OTHER_DEVICE,
    geofenceId: "gf-home",
    geofenceName: "Home",
    lat: 51.06,
    lon: 3.72,
    radiusM: 100,
    transition: "enter",
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
  });

  // Owned group: CALLER owner, OTHER_MEMBER co-member.
  await deps.groupRepo.createGroupMeta({
    groupId: OWNED_GROUP,
    name: "Festival crew",
    ownerUserId: CALLER,
    createdAt: "2026-07-19T08:00:00Z",
    endsAt: "2026-07-21T08:00:00Z",
    expiryPolicy: "delete",
    code: "OWNCODE1",
  });
  await deps.groupRepo.addMember(OWNED_GROUP, { userId: CALLER, role: "owner", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.groupRepo.addMember(OWNED_GROUP, { userId: OTHER_MEMBER, role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.groupCodeRepo.createCode("OWNCODE1", { groupId: OWNED_GROUP, createdAt: "2026-07-19T08:00:00Z" });
  await deps.groupLastKnownRepo.upsertIfNewer(OWNED_GROUP, {
    userId: CALLER,
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    syncIntervalMinutes: 15,
  });
  await deps.groupExpiryRepo.putExpiryRow("2026-07-21", OWNED_GROUP, "expire");
  await deps.userRepo.addGroupMembership(CALLER, { groupId: OWNED_GROUP, role: "owner", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.userRepo.addGroupMembership(OTHER_MEMBER, { groupId: OWNED_GROUP, role: "member", joinedAt: "2026-07-19T08:00:00Z" });

  // Joined group: OTHER_MEMBER owner, CALLER member.
  await deps.groupRepo.createGroupMeta({
    groupId: JOINED_GROUP,
    name: "Hiking trip",
    ownerUserId: OTHER_MEMBER,
    createdAt: "2026-07-19T08:00:00Z",
    endsAt: "2026-07-21T08:00:00Z",
    expiryPolicy: "delete",
    code: "JOINCODE1",
  });
  await deps.groupRepo.addMember(JOINED_GROUP, { userId: OTHER_MEMBER, role: "owner", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.groupRepo.addMember(JOINED_GROUP, { userId: CALLER, role: "member", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.groupCodeRepo.createCode("JOINCODE1", { groupId: JOINED_GROUP, createdAt: "2026-07-19T08:00:00Z" });
  await deps.groupLastKnownRepo.upsertIfNewer(JOINED_GROUP, {
    userId: CALLER,
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    recordedAt: "2026-07-19T08:00:00Z",
    receivedAt: "2026-07-19T08:00:01Z",
    syncIntervalMinutes: 15,
  });
  await deps.groupExpiryRepo.putExpiryRow("2026-07-21", JOINED_GROUP, "expire");
  await deps.userRepo.addGroupMembership(OTHER_MEMBER, { groupId: JOINED_GROUP, role: "owner", joinedAt: "2026-07-19T08:00:00Z" });
  await deps.userRepo.addGroupMembership(CALLER, { groupId: JOINED_GROUP, role: "member", joinedAt: "2026-07-19T08:00:00Z" });
}

/** Asserts every §2 "account delete" row for CALLER is gone, and every corresponding row for
 * OTHER_MEMBER (and the joined group's owner-side data) is untouched.
 *
 * `idempotencyMarkersCleaned` is false only for crash-boundary tests that simulate the
 * subject's Devices partition already being gone BEFORE deleteAccount is (re-)called — per
 * 002 §4.2's documented, accepted edge, once the device list can no longer be collected, its
 * IdempotencyMarkers partition is orphaned forever ("on retry: none left, skip").
 *
 * `locateControlRowSurvives`, `otherMemberEventSurvives`, and `familyUsageSurvives` are false
 * only for the cascade path, where the WHOLE family footprint (LocateRequests partition,
 * history/events prefix, family-keyed Usage partition) is wiped for every member — not just
 * the rows/lines naming the departing subject. */
async function assertCallerFullyErased(
  deps: DeleteAccountDeps,
  opts: {
    idempotencyMarkersCleaned?: boolean;
    locateControlRowSurvives?: boolean;
    otherMemberEventSurvives?: boolean;
    ownedGroupExpiryRowCleaned?: boolean;
    familyUsageSurvives?: boolean;
  } = {},
): Promise<void> {
  const {
    idempotencyMarkersCleaned = true,
    locateControlRowSurvives = true,
    otherMemberEventSurvives = true,
    ownedGroupExpiryRowCleaned = true,
    familyUsageSurvives = true,
  } = opts;

  expect(await deps.deviceRepo.listDevices(CALLER)).toEqual([]);
  expect(await deps.lastKnownRepo.listByOwner(CALLER)).toEqual([]);
  expect(await deps.userRepo.getProfile(CALLER)).toBeNull();

  // CALLER's own uid-keyed Usage partition (002 §4.2 step 6, B18 follow-up) — unconditional
  // on family membership/cascade. Family-keyed usage is a separate check below.
  expect(await deps.usageRepo.get(CALLER, "apiCalls", "2026-07-18")).toBe(0);
  if (familyUsageSurvives) {
    expect(await deps.usageRepo.get(FAMILY_ID, "apiCalls", "2026-07-19")).toBe(1); // non-cascade: family-keyed rows are untouched
  } else {
    expect(await deps.usageRepo.get(FAMILY_ID, "apiCalls", "2026-07-19")).toBe(0); // cascade: whole family partition gone
  }

  // Idempotency markers: CALLER's device partition (read-only check — see the doc above for
  // why this is sometimes expected to still be present), OTHER's always untouched.
  const idem = deps.idempotencyRepo as InMemoryIdempotencyRepo;
  expect(idem.hasAnyMarker(CALLER_DEVICE)).toBe(!idempotencyMarkersCleaned);
  expect(idem.hasAnyMarker(OTHER_DEVICE)).toBe(true);

  const locateIds = ["lr_00000000000000000001", "lr_00000000000000000002", "lr_00000000000000000003"];
  const [r1, r2, r3] = await Promise.all(locateIds.map((id) => deps.locateRequestRepo.get(FAMILY_ID, id)));
  expect(r1).toBeNull(); // requestedBy === CALLER
  expect(r2).toBeNull(); // targetUserId === CALLER
  if (locateControlRowSurvives) {
    expect(r3).not.toBeNull(); // names neither — survives the non-cascade path
  } else {
    expect(r3).toBeNull(); // the cascade wipes the WHOLE family partition, r3 included
  }

  // Owned group: fully gone, INCLUDING its GroupExpiry row (bucketed at date(meta.endsAt) —
  // "2026-07-21T08:00:00Z" truncated to "2026-07-21" — proving the exact bucket-date
  // computation, not just that some cleanup happened).
  expect(await deps.groupRepo.getGroupMeta(OWNED_GROUP)).toBeNull();
  expect(await deps.groupRepo.listMembers(OWNED_GROUP)).toEqual([]);
  expect(await deps.groupCodeRepo.getCode("OWNCODE1")).toBeNull();
  expect(await deps.groupLastKnownRepo.listByGroup(OWNED_GROUP)).toEqual([]);
  expect(await deps.userRepo.listGroupMemberships(OTHER_MEMBER)).not.toContainEqual(
    expect.objectContaining({ groupId: OWNED_GROUP }),
  );
  if (ownedGroupExpiryRowCleaned) {
    expect((deps.groupExpiryRepo as InMemoryGroupExpiryRepo).get("2026-07-21", OWNED_GROUP)).toBeUndefined();
  }

  // Joined group: survives, only CALLER's membership/position gone.
  expect(await deps.groupRepo.getGroupMeta(JOINED_GROUP)).not.toBeNull();
  expect(await deps.groupRepo.getMember(JOINED_GROUP, CALLER)).toBeNull();
  expect(await deps.groupRepo.getMember(JOINED_GROUP, OTHER_MEMBER)).not.toBeNull();
  expect(await deps.groupLastKnownRepo.get(JOINED_GROUP, CALLER)).toBeNull();
  expect(await deps.userRepo.listGroupMemberships(CALLER)).toEqual([]);

  // Events: CALLER's line always gone; OTHER_MEMBER's line survives UNLESS the cascade
  // wiped the whole family prefix (family deletion erases every member's events too).
  const events = await deps.historyStore.readEventHistory(FAMILY_ID, "2026-07-19", "2026-07-19", undefined, 10, null);
  expect(events.items.map((e) => e.eventId)).toEqual(otherMemberEventSurvives ? ["evt-other"] : []);

  // CALLER's own history prefix gone.
  const callerFixes = await deps.historyStore.readFixHistory(FAMILY_ID, CALLER, undefined, "2026-07-19", "2026-07-19", 10, null);
  expect(callerFixes.items).toEqual([]);
}

describe("domain/user/deleteAccount", () => {
  it("erases every account-delete row for a non-cascade caller (co-parent remains), leaving the family intact for others", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    await assertCallerFullyErased(deps);
    // Family survives for others (008 §4.2 non-cascade path).
    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).not.toBeNull();
    expect(await deps.familyRepo.listMembers(FAMILY_ID)).toEqual(
      expect.arrayContaining([expect.objectContaining({ userId: OTHER_PARENT }), expect.objectContaining({ userId: OTHER_MEMBER })]),
    );
    expect(await deps.familyRepo.listMembers(FAMILY_ID)).not.toContainEqual(expect.objectContaining({ userId: CALLER }));
    expect(await deps.userRepo.getProfile(OTHER_MEMBER)).toEqual({ familyId: FAMILY_ID, role: "member", displayName: "Noor" });
    expect(await deps.userRepo.getProfile(OTHER_PARENT)).toEqual({ familyId: FAMILY_ID, role: "parent", displayName: "Ines" });
    // OTHER_MEMBER's own devices/last-known are untouched.
    expect(await deps.deviceRepo.listDevices(OTHER_MEMBER)).toHaveLength(1);
    expect(await deps.lastKnownRepo.listByOwner(OTHER_MEMBER)).toHaveLength(1);
    const otherFixes = await deps.historyStore.readFixHistory(FAMILY_ID, OTHER_MEMBER, undefined, "2026-07-19", "2026-07-19", 10, null);
    expect(otherFixes.items).toHaveLength(1);
    // Entitlements/usage untouched (family survives).
    expect(await deps.entitlementsRepo.get(FAMILY_ID)).not.toBeNull();
  });

  it("cascades to full family deletion when the caller is the LAST PARENT (no other parent remains)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "parent", includeOtherParent: false });

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "parent" }, deps);

    await assertCallerFullyErased(deps, {
      locateControlRowSurvives: false,
      otherMemberEventSurvives: false,
      familyUsageSurvives: false,
    });
    // Whole family gone (008 §4.2 cascade path).
    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
    expect(await deps.entitlementsRepo.get(FAMILY_ID)).toBeNull();
    // Other member's account SURVIVES, family-less (008 §5.2) — devices/last-known untouched.
    expect(await deps.userRepo.getProfile(OTHER_MEMBER)).toEqual({ familyId: null, role: null, displayName: "Noor" });
    expect(await deps.deviceRepo.listDevices(OTHER_MEMBER)).toHaveLength(1);
    expect(await deps.lastKnownRepo.listByOwner(OTHER_MEMBER)).toHaveLength(1);
  });

  it("cascades to full family deletion when the caller is the SOLE MEMBER", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({ familyId: FAMILY_ID, familyName: "Solo", createdBy: CALLER, createdAt: "2026-07-19T08:00:00Z" });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
    await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "parent" }, deps);

    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
  });

  // The "sole member" clause of the cascade condition (008 §4.2) is independent of the
  // "caller is a parent" clause — defense in depth against a stale/incorrect `role` snapshot
  // in the auth context: a truly sole member (no OTHER member at all) must cascade regardless
  // of what `role` claims, since there is nobody else's data to protect from a wrongful
  // cascade either way.
  it("cascades for a sole member even when the (defensively untrusted) role snapshot says non-parent", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({ familyId: FAMILY_ID, familyName: "Solo", createdBy: CALLER, createdAt: "2026-07-19T08:00:00Z" });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
    await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
  });

  it("does NOT cascade when a co-parent remains, even though the caller themself is a parent — and even with a non-parent child ALSO in the roster (mixed-role otherMembers)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({ familyId: FAMILY_ID, familyName: "Wauters", createdBy: CALLER, createdAt: "2026-07-19T08:00:00Z" });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: OTHER_PARENT, role: "parent", displayName: "Ines", joinedAt: "2026-07-19T08:00:00Z" });
    // A non-parent child ALSO in the roster: otherMembers is now a MIX of parent + non-parent
    // roles, which is what distinguishes "some other member is a parent" from "every other
    // member is a parent" (the latter would be false here, wrongly implying no parent left).
    await deps.familyRepo.addMember(FAMILY_ID, { userId: OTHER_MEMBER, role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
    await deps.userRepo.createProfile(OTHER_PARENT, { familyId: FAMILY_ID, role: "parent", displayName: "Ines" });
    await deps.userRepo.createProfile(OTHER_MEMBER, { familyId: FAMILY_ID, role: "member", displayName: "Noor" });
    await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "parent" }, deps);

    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).not.toBeNull();
    expect(await deps.familyRepo.listMembers(FAMILY_ID)).toEqual(
      expect.arrayContaining([expect.objectContaining({ userId: OTHER_PARENT }), expect.objectContaining({ userId: OTHER_MEMBER })]),
    );
    expect(await deps.userRepo.getProfile(OTHER_PARENT)).toEqual({ familyId: FAMILY_ID, role: "parent", displayName: "Ines" });
    expect(await deps.userRepo.getProfile(OTHER_MEMBER)).toEqual({ familyId: FAMILY_ID, role: "member", displayName: "Noor" });
    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
  });

  // Security review-gate finding (BLOCKING, 000 §O19): the Families roster has no ETag
  // guard, so two parents calling DELETE /users/me concurrently can each observe the other
  // and both take the non-cascade branch, leaving the family with ZERO parents. The
  // narrowed cascade condition (008 §4.2) requires the CALLER to BE a parent — a remaining
  // non-parent child must NEVER cascade, even in this already-broken, parent-less state.
  it("does NOT cascade for a non-parent caller in an already parent-less family (000 §O19's race — the narrowed condition contains the blast radius)", async () => {
    const deps = buildDeps();
    // Simulates the aftermath of the 000 §O19 race directly (no parent survives), rather
    // than the race itself — the point under test is the CONDITION, not the race.
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: "gone-parent-uid",
      createdAt: "2026-07-19T08:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: CALLER, role: "member", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.familyRepo.addMember(FAMILY_ID, { userId: OTHER_MEMBER, role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z" });
    await deps.userRepo.createProfile(CALLER, { familyId: FAMILY_ID, role: "member", displayName: "Eric" });
    await deps.userRepo.createProfile(OTHER_MEMBER, { familyId: FAMILY_ID, role: "member", displayName: "Noor" });
    await deps.entitlementsRepo.create(FAMILY_ID, "free", "2026-07-19T08:00:00Z");

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    // The family (and OTHER_MEMBER's membership in it) survives — only CALLER is erased.
    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).not.toBeNull();
    expect(await deps.entitlementsRepo.get(FAMILY_ID)).not.toBeNull();
    expect(await deps.familyRepo.listMembers(FAMILY_ID)).toEqual([expect.objectContaining({ userId: OTHER_MEMBER })]);
    expect(await deps.userRepo.getProfile(OTHER_MEMBER)).toEqual({ familyId: FAMILY_ID, role: "member", displayName: "Noor" });
    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
  });

  // Security review-gate finding (Major, 002 §4.2 step 6): 002 §4.2's numbered ordering list
  // originally omitted the subject's uid-keyed Usage partition entirely. apiCalls is keyed
  // profile?.familyId ?? uid (B14), so a CURRENT family member can still hold uid-keyed rows
  // from any earlier family-less period — those must be erased too, while the family-keyed
  // rows (household aggregates) must NOT be touched by a non-cascade account deletion.
  it("erases the subject's own uid-keyed Usage partition even as a CURRENT family member, while family-keyed rows survive (non-cascade path)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });
    // Extra uid-keyed rows across two metrics/dates, on top of seedScenario's own apiCalls
    // row, to prove the WHOLE uid partition goes, not just one row.
    await deps.usageRepo.increment(CALLER, "locationBatches", "2026-07-17");
    await deps.usageRepo.increment(CALLER, "apiCalls", "2026-07-18", 4);

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    expect(await deps.usageRepo.get(CALLER, "apiCalls", "2026-07-18")).toBe(0);
    expect(await deps.usageRepo.get(CALLER, "locationBatches", "2026-07-17")).toBe(0);
    // Family-keyed usage is untouched — the family survives (co-parent remains).
    expect(await deps.usageRepo.get(FAMILY_ID, "apiCalls", "2026-07-19")).toBe(1);
  });

  it("erases the subject's uid-keyed Usage partition unconditionally, even for a family-less caller", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile(CALLER, { familyId: null, role: null, displayName: "Eric" });
    await deps.usageRepo.increment(CALLER, "apiCalls", "2026-07-18");

    await deleteAccount({ uid: CALLER, familyId: null, role: null }, deps);

    expect(await deps.usageRepo.get(CALLER, "apiCalls", "2026-07-18")).toBe(0);
  });

  it("is a 204 no-op for a caller with no profile at all (specs/008 §4.1)", async () => {
    const deps = buildDeps();

    await expect(deleteAccount({ uid: "ghost-uid", familyId: null, role: null }, deps)).resolves.toBeUndefined();

    expect(await deps.userRepo.getProfile("ghost-uid")).toBeNull();
    expect(await deps.deviceRepo.listDevices("ghost-uid")).toEqual([]);
  });

  it("erases a family-less caller's devices/last-known/groups and deletes their profile, untouched by any family step", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile(CALLER, { familyId: null, role: null, displayName: "Eric" });
    await deps.deviceRepo.putDevice(CALLER, {
      deviceId: CALLER_DEVICE,
      ownerUserId: CALLER,
      platform: "android",
      model: "Pixel",
      appVersion: "1.0",
      deviceName: "Eric's phone",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-19T08:00:00Z",
      lastSeenAt: "2026-07-19T08:00:00Z",
    });

    await deleteAccount({ uid: CALLER, familyId: null, role: null }, deps);

    expect(await deps.deviceRepo.listDevices(CALLER)).toEqual([]);
    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
  });

  it("never touches any family-scoped storage for a family-less caller (steps 4/6/7 must not run at all)", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile(CALLER, { familyId: null, role: null, displayName: "Eric" });
    let locateCalls = 0;
    let listMembersCalls = 0;
    let deleteUserPrefixCalls = 0;
    let eraseEventsCalls = 0;
    let removeMemberCalls = 0;

    const realDeleteRowsForUser = deps.locateRequestRepo.deleteRowsForUser.bind(deps.locateRequestRepo);
    deps.locateRequestRepo.deleteRowsForUser = async (familyId, userId) => {
      locateCalls += 1;
      return realDeleteRowsForUser(familyId, userId);
    };
    const realListMembers = deps.familyRepo.listMembers.bind(deps.familyRepo);
    deps.familyRepo.listMembers = async (familyId) => {
      listMembersCalls += 1;
      return realListMembers(familyId);
    };
    const realDeleteUserPrefix = deps.historyStore.deleteUserPrefix.bind(deps.historyStore);
    deps.historyStore.deleteUserPrefix = async (familyId, userId) => {
      deleteUserPrefixCalls += 1;
      return realDeleteUserPrefix(familyId, userId);
    };
    const realEraseUserFromEvents = deps.historyStore.eraseUserFromEvents.bind(deps.historyStore);
    deps.historyStore.eraseUserFromEvents = async (familyId, userId) => {
      eraseEventsCalls += 1;
      return realEraseUserFromEvents(familyId, userId);
    };
    const realRemoveMember = deps.familyRepo.removeMember.bind(deps.familyRepo);
    deps.familyRepo.removeMember = async (familyId, userId) => {
      removeMemberCalls += 1;
      return realRemoveMember(familyId, userId);
    };

    await deleteAccount({ uid: CALLER, familyId: null, role: null }, deps);

    expect(locateCalls).toBe(0);
    expect(listMembersCalls).toBe(0);
    expect(deleteUserPrefixCalls).toBe(0);
    expect(eraseEventsCalls).toBe(0);
    expect(removeMemberCalls).toBe(0);
    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
  });

  it("performs devices FIRST and the Users profile row LAST (specs/002 §4.2 ordering)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });
    const order: string[] = [];

    const realDeleteDevicesByOwner = deps.deviceRepo.deleteDevicesByOwner.bind(deps.deviceRepo);
    deps.deviceRepo.deleteDevicesByOwner = async (ownerUserId) => {
      order.push("devices");
      return realDeleteDevicesByOwner(ownerUserId);
    };
    const realDeleteByOwner = deps.lastKnownRepo.deleteByOwner.bind(deps.lastKnownRepo);
    deps.lastKnownRepo.deleteByOwner = async (ownerUserId) => {
      order.push("lastKnown");
      return realDeleteByOwner(ownerUserId);
    };
    const realRemoveMember = deps.familyRepo.removeMember.bind(deps.familyRepo);
    deps.familyRepo.removeMember = async (familyId, userId) => {
      order.push("familyMember");
      return realRemoveMember(familyId, userId);
    };
    const realDeleteProfile = deps.userRepo.deleteProfile.bind(deps.userRepo);
    deps.userRepo.deleteProfile = async (userId) => {
      order.push("profile");
      return realDeleteProfile(userId);
    };

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    expect(order[0]).toBe("devices");
    expect(order[order.length - 1]).toBe("profile");
    expect(order.indexOf("devices")).toBeLessThan(order.indexOf("lastKnown"));
    expect(order.indexOf("familyMember")).toBeLessThan(order.indexOf("profile"));
  });

  it("self-heals an orphaned owned-group reverse-index row whose Groups meta is already gone", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile(CALLER, { familyId: null, role: null, displayName: "Eric" });
    // A reverse-index row pointing at a group whose meta was already fully torn down
    // elsewhere (e.g. the sweeper) — the meta point-read below MUST return null.
    await deps.userRepo.addGroupMembership(CALLER, { groupId: "grp_gone00000000000", role: "owner", joinedAt: "2026-07-19T08:00:00Z" });

    await expect(deleteAccount({ uid: CALLER, familyId: null, role: null }, deps)).resolves.toBeUndefined();

    expect(await deps.userRepo.listGroupMemberships(CALLER)).toEqual([]);
  });

  // --- crash-retry idempotency at each step boundary (specs/008 §9 requires this) ---

  it("converges to full erasure on a re-call after a simulated crash mid-step-1 (devices already gone, nothing else touched)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });
    await deps.deviceRepo.deleteDevicesByOwner(CALLER);

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    // Devices were already gone BEFORE this call, so the deviceId list could not be
    // re-collected — CALLER_DEVICE's IdempotencyMarkers partition is orphaned (accepted,
    // documented edge, 002 §4.2: "on retry: none left, skip").
    await assertCallerFullyErased(deps, { idempotencyMarkersCleaned: false });
  });

  it("converges after a simulated crash mid-step-5 (owned group already fully torn down, joined-group leave not yet done)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });
    await deps.deviceRepo.deleteDevicesByOwner(CALLER);
    await deps.lastKnownRepo.deleteByOwner(CALLER);
    await deps.locateRequestRepo.deleteRowsForUser(FAMILY_ID, CALLER);
    // Owned group hard delete (INCLUDING its GroupExpiry row) already ran to completion in
    // the "crashed" prior attempt — the crash happened at the natural per-group iteration
    // boundary, between finishing OWNED_GROUP and starting JOINED_GROUP's leave semantics.
    const ownedMeta = await deps.groupRepo.getGroupMeta(OWNED_GROUP);
    if (ownedMeta) {
      const members = await deps.groupRepo.listMembers(OWNED_GROUP);
      for (const m of members) await deps.userRepo.removeGroupMembership(m.userId, OWNED_GROUP);
      await deps.groupLastKnownRepo.deletePartition(OWNED_GROUP);
      await deps.groupCodeRepo.deleteCode(ownedMeta.code);
      for (const m of members) await deps.groupRepo.removeMember(OWNED_GROUP, m.userId);
      await deps.groupRepo.deleteGroupMeta(OWNED_GROUP);
      await deps.groupExpiryRepo.deleteExpiryRow("2026-07-21", OWNED_GROUP);
    }

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    await assertCallerFullyErased(deps, { idempotencyMarkersCleaned: false });
  });

  it("converges after a simulated crash right after the events rewrite but before the Families member row is removed (non-cascade path)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });
    await deps.deviceRepo.deleteDevicesByOwner(CALLER);
    await deps.lastKnownRepo.deleteByOwner(CALLER);
    await deps.locateRequestRepo.deleteRowsForUser(FAMILY_ID, CALLER);
    await deps.historyStore.deleteUserPrefix(FAMILY_ID, CALLER);
    await deps.historyStore.eraseUserFromEvents(FAMILY_ID, CALLER);
    // Families member row deliberately NOT removed yet; Users profile also untouched.

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    await assertCallerFullyErased(deps, { idempotencyMarkersCleaned: false });
    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).not.toBeNull();
  });

  it("converges after a crash right after the Families member row is removed but before the Users profile row (non-cascade path, the profile is still the retry pointer)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });
    await deps.deviceRepo.deleteDevicesByOwner(CALLER);
    await deps.lastKnownRepo.deleteByOwner(CALLER);
    await deps.locateRequestRepo.deleteRowsForUser(FAMILY_ID, CALLER);
    await deps.historyStore.deleteUserPrefix(FAMILY_ID, CALLER);
    await deps.historyStore.eraseUserFromEvents(FAMILY_ID, CALLER);
    await deps.familyRepo.removeMember(FAMILY_ID, CALLER);
    // Users profile row (the retry pointer) is untouched — still shows the old familyId.
    expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: FAMILY_ID, role: "member", displayName: "Eric" });

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);

    await assertCallerFullyErased(deps, { idempotencyMarkersCleaned: false });
  });

  it("converges after a crash mid-cascade (family footprint partially done, caller's own profile still points at the gone family)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "parent", includeOtherParent: false });
    await deps.deviceRepo.deleteDevicesByOwner(CALLER);
    await deps.lastKnownRepo.deleteByOwner(CALLER);
    await deps.locateRequestRepo.deleteRowsForUser(FAMILY_ID, CALLER);
    // Simulate the family footprint having run through its own step 5 (Families meta gone)
    // but crashing before its step 6 (the caller's own clearFamilyMembership flip).
    await deps.userRepo.updateProfile(OTHER_MEMBER, { familyId: null, role: null });
    await deps.familyRepo.removeMember(FAMILY_ID, OTHER_MEMBER);
    await deps.familyRepo.removeMember(FAMILY_ID, CALLER);
    await deps.entitlementsRepo.delete(FAMILY_ID);
    await deps.usageRepo.deletePartition(FAMILY_ID);
    await deps.locateRequestRepo.deletePartition(FAMILY_ID);
    await deps.historyStore.deleteFamilyPrefix(FAMILY_ID);
    await deps.geofenceConfigRepo.deleteConfig(FAMILY_ID);
    await deps.familyRepo.deleteFamilyMeta(FAMILY_ID);
    expect(await deps.userRepo.getProfile(CALLER)).toEqual({ familyId: FAMILY_ID, role: "parent", displayName: "Eric" });

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "parent" }, deps);

    expect(await deps.userRepo.getProfile(CALLER)).toBeNull();
    expect(await deps.familyRepo.getFamilyMeta(FAMILY_ID)).toBeNull();
  });

  it("is a full no-op the second time it is called after a clean completion (general re-call idempotency)", async () => {
    const deps = buildDeps();
    await seedScenario(deps, { callerRole: "member", includeOtherParent: true });

    await deleteAccount({ uid: CALLER, familyId: FAMILY_ID, role: "member" }, deps);
    await assertCallerFullyErased(deps);

    // A literal retry now sees familyId: null (the profile is gone) — same as the real
    // authGuard would resolve for a profile-less retry (008 §4.1).
    await expect(deleteAccount({ uid: CALLER, familyId: null, role: null }, deps)).resolves.toBeUndefined();
    await assertCallerFullyErased(deps);
  });
});
