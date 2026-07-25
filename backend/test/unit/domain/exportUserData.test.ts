import { describe, expect, it, vi } from "vitest";
import { exportUserData } from "../../../src/domain/export/exportUserData";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupLastKnownRepo } from "../../fakes/inMemoryGroupLastKnownRepo";
import { InMemoryHistoryStore } from "../../fakes/inMemoryHistoryStore";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const PARENT_ID = "u1";
const MEMBER_ID = "u2";
const NOW = "2026-07-25T14:00:00Z";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  return {
    userRepo: new InMemoryUserRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    deviceRepo: new InMemoryDeviceRepo(),
    lastKnownRepo: new InMemoryLastKnownRepo(),
    groupRepo: new InMemoryGroupRepo(),
    groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
    historyStore: new InMemoryHistoryStore(),
    usageRepo: new InMemoryUsageRepo(),
    entitlementsRepo,
    clock: new FixedClock(new Date(NOW)),
  };
}

async function seedFamily(deps: ReturnType<typeof buildDeps>) {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: PARENT_ID,
    createdAt: "2026-06-01T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: PARENT_ID,
    role: "parent",
    displayName: "Eric",
    joinedAt: "2026-06-01T08:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: MEMBER_ID,
    role: "member",
    displayName: "Noor",
    joinedAt: "2026-06-02T08:30:00Z",
  });
  await deps.userRepo.createProfile(PARENT_ID, { familyId: FAMILY_ID, role: "parent", displayName: "Eric" });
  await deps.userRepo.createProfile(MEMBER_ID, { familyId: FAMILY_ID, role: "member", displayName: "Noor" });
}

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: "device-2a",
    ownerUserId: MEMBER_ID,
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Noor's phone",
    pushToken: "fcm-super-secret-token",
    locationPushToken: "apns-loc-secret",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-06-02T09:00:00Z",
    lastSeenAt: "2026-07-25T09:00:00Z",
    ...overrides,
  };
}

describe("domain/export/exportUserData (specs/001 §13.1, specs/008 §3)", () => {
  it("throws AUTH_FORBIDDEN when a non-parent requests another user's export", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      exportUserData(
        { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: { userId: PARENT_ID } },
        deps,
      ),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws AUTH_FORBIDDEN when a family-less caller requests another user's export", async () => {
    const deps = buildDeps();

    await expectAppError(
      exportUserData({ uid: "solo", familyId: null, role: null, query: { userId: "someone-else" } }, deps),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws MEMBER_NOT_FOUND when a parent names a non-member", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      exportUserData(
        { uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: { userId: "ghost" } },
        deps,
      ),
      "MEMBER_NOT_FOUND",
    );
  });

  it("throws MEMBER_NOT_FOUND for a removed ex-member (not in the current roster)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.familyRepo.removeMember(FAMILY_ID, MEMBER_ID);

    await expectAppError(
      exportUserData(
        { uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: { userId: MEMBER_ID } },
        deps,
      ),
      "MEMBER_NOT_FOUND",
    );
  });

  it("throws VALIDATION_FAILED for a malformed userId query param", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      exportUserData(
        { uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: { userId: "bad/id#here" } },
        deps,
      ),
      "VALIDATION_FAILED",
    );
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = {
      userRepo: new InMemoryUserRepo(),
      familyRepo: new InMemoryFamilyRepo(),
      deviceRepo: new InMemoryDeviceRepo(),
      lastKnownRepo: new InMemoryLastKnownRepo(),
      groupRepo: new InMemoryGroupRepo(),
      groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
      historyStore: new InMemoryHistoryStore(),
      usageRepo: new InMemoryUsageRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // not seeded
      clock: new FixedClock(new Date(NOW)),
    };
    await seedFamily(deps);

    await expectAppError(
      exportUserData({ uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: {} }, deps),
      "INTERNAL_ERROR",
    );
  });

  it('throws LIMIT_EXCEEDED with details.limit "exportsPerDay" once the free-plan daily quota (3) is reached', async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.usageRepo.increment(FAMILY_ID, "exports", "2026-07-25", 3); // free plan limit

    await expectAppError(
      exportUserData({ uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: {} }, deps),
      "LIMIT_EXCEEDED",
      { limit: "exportsPerDay" },
    );
  });

  it("does not throw LIMIT_EXCEEDED one below the quota, and increments exports usage on success", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.usageRepo.increment(FAMILY_ID, "exports", "2026-07-25", 2);

    await exportUserData({ uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: {} }, deps);

    expect(await deps.usageRepo.get(FAMILY_ID, "exports", "2026-07-25")).toBe(3);
  });

  it("counts the quota against the CALLER, not the exported subject, on a cross-export", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await exportUserData(
      { uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: { userId: MEMBER_ID } },
      deps,
    );

    // Usage is family-keyed for both members (same family) — the single family partition
    // counter increments regardless of which member the export targeted.
    expect(await deps.usageRepo.get(FAMILY_ID, "exports", "2026-07-25")).toBe(1);
  });

  it("self-export: builds the full document for the caller (own userId defaulted)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(MEMBER_ID, device());
    deps.lastKnownRepo.seed(MEMBER_ID, {
      deviceId: "device-2a",
      lat: 51.05,
      lon: 3.71,
      accuracyM: 12.5,
      batteryPct: 78,
      recordedAt: "2026-07-25T09:00:00Z",
      receivedAt: "2026-07-25T09:00:02Z",
      source: "periodic",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.formatVersion).toBe(1);
    expect(doc.generatedAt).toBe(new Date(NOW).toISOString());
    expect(doc.subject).toEqual({ userId: MEMBER_ID, displayName: "Noor" });
    expect(doc.family).toEqual({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      role: "member",
      joinedAt: "2026-06-02T08:30:00Z",
    });
    expect(doc.devices).toEqual([
      {
        deviceId: "device-2a",
        ownerUserId: MEMBER_ID,
        platform: "android",
        model: "Pixel 8",
        appVersion: "1.0.0",
        deviceName: "Noor's phone",
        pushInvalid: false,
        syncIntervalMinutes: 15,
        trackingEnabled: true,
      },
    ]);
    // Push tokens (write-only, 001 §4.1) never leak into the export (008 §2).
    expect(doc.devices[0]).not.toHaveProperty("pushToken");
    expect(doc.devices[0]).not.toHaveProperty("locationPushToken");

    expect(doc.lastKnown).toEqual([
      {
        deviceId: "device-2a",
        lat: 51.05,
        lon: 3.71,
        accuracyM: 12.5,
        batteryPct: 78,
        recordedAt: "2026-07-25T09:00:00Z",
        receivedAt: "2026-07-25T09:00:02Z",
        source: "periodic",
      },
    ]);

    expect(doc.providerData).toEqual({
      firebaseAuthentication:
        "Your phone number and sign-in metadata are held by Firebase Authentication, not by Findly; they are deleted when your account is deleted.",
    });
  });

  it("parent-for-member: exports another current family member's data, subject fields reflect the TARGET not the caller", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(MEMBER_ID, device());

    const doc = await exportUserData(
      { uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: { userId: MEMBER_ID } },
      deps,
    );

    expect(doc.subject).toEqual({ userId: MEMBER_ID, displayName: "Noor" });
    expect(doc.family).toEqual({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      role: "member",
      joinedAt: "2026-06-02T08:30:00Z",
    });
    expect(doc.devices).toHaveLength(1);
    expect(doc.devices[0]!.ownerUserId).toBe(MEMBER_ID);
  });

  it("throws INTERNAL_ERROR when the caller is missing from their own family roster (data-integrity guard)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: PARENT_ID,
      createdAt: "2026-06-01T08:00:00Z",
    });
    // Deliberately no addMember(PARENT_ID, ...) — the roster disagrees with the auth context.
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: MEMBER_ID,
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-06-02T08:30:00Z",
    });

    await expectAppError(
      exportUserData({ uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: {} }, deps),
      "INTERNAL_ERROR",
    );
  });

  it("throws INTERNAL_ERROR when a cross-export target's family meta is missing (crash mid-something, data-integrity guard)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.familyRepo.deleteMetaOnlyForTest(FAMILY_ID);

    await expectAppError(
      exportUserData(
        { uid: PARENT_ID, familyId: FAMILY_ID, role: "parent", query: { userId: MEMBER_ID } },
        deps,
      ),
      "INTERNAL_ERROR",
    );
  });

  it("throws INTERNAL_ERROR when the caller's own family meta is missing on self-export (crash mid-something, data-integrity guard)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.familyRepo.deleteMetaOnlyForTest(FAMILY_ID);

    await expectAppError(
      exportUserData({ uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} }, deps),
      "INTERNAL_ERROR",
    );
  });

  it("self-export, family-less caller: family is null, no location history/geofence events queried", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile("solo", { familyId: null, role: null, displayName: "Solo" });
    deps.deviceRepo.seed("solo", device({ deviceId: "solo-device", ownerUserId: "solo" }));

    const doc = await exportUserData({ uid: "solo", familyId: null, role: null, query: {} }, deps);

    expect(doc.subject).toEqual({ userId: "solo", displayName: "Solo" });
    expect(doc.family).toBeNull();
    expect(doc.locationHistory).toEqual([]);
    expect(doc.geofenceEvents).toEqual([]);
    expect(doc.devices).toHaveLength(1);
  });

  it("never queries HistoryStore at all for a family-less subject (subjectFamilyId gate)", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile("solo", { familyId: null, role: null, displayName: "Solo" });
    const fixSpy = vi.spyOn(deps.historyStore, "readFixHistory");
    const eventSpy = vi.spyOn(deps.historyStore, "readEventHistory");

    await exportUserData({ uid: "solo", familyId: null, role: null, query: {} }, deps);

    expect(fixSpy).not.toHaveBeenCalled();
    expect(eventSpy).not.toHaveBeenCalled();
  });

  it("falls back to uid as displayName for a family-less caller with no profile row (defensive)", async () => {
    const deps = buildDeps();

    const doc = await exportUserData({ uid: "ghost-uid", familyId: null, role: null, query: {} }, deps);

    expect(doc.subject).toEqual({ userId: "ghost-uid", displayName: "ghost-uid" });
  });

  it("location history: includes a fix 200 days back — beyond historyDays(90), within the 400-day retention window", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.historyStore.appendFix(FAMILY_ID, MEMBER_ID, "device-2a", {
      fixId: "fix-old",
      recordedAt: "2026-01-06T14:00:00Z", // 200 days before NOW
      receivedAt: "2026-01-06T14:00:02Z",
      lat: 51.0,
      lon: 3.7,
      accuracyM: 10,
      batteryPct: 50,
      source: "periodic",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.locationHistory.map((f) => f.fixId)).toEqual(["fix-old"]);
  });

  it("location history: excludes a fix 401 days back — outside the 400-day physical retention window", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.historyStore.appendFix(FAMILY_ID, MEMBER_ID, "device-2a", {
      fixId: "fix-too-old",
      recordedAt: "2025-06-19T14:00:00Z", // 401 days before NOW
      receivedAt: "2025-06-19T14:00:02Z",
      lat: 51.0,
      lon: 3.7,
      accuracyM: 10,
      batteryPct: 50,
      source: "periodic",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.locationHistory).toEqual([]);
  });

  it("location history: internally exhausts HistoryStore's cursor pagination (501 fixes on one day, above the 500 internal page size)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    for (let i = 0; i < 501; i++) {
      const minute = String(i % 60).padStart(2, "0");
      const hour = String(Math.floor(i / 60)).padStart(2, "0");
      await deps.historyStore.appendFix(FAMILY_ID, MEMBER_ID, "device-2a", {
        fixId: `fix-${String(i).padStart(4, "0")}`,
        recordedAt: `2026-07-24T${hour}:${minute}:00Z`,
        receivedAt: `2026-07-24T${hour}:${minute}:02Z`,
        lat: 51.0,
        lon: 3.7,
        accuracyM: 10,
        batteryPct: 50,
        source: "periodic",
      });
    }

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.locationHistory).toHaveLength(501);
    expect(doc.locationHistory.map((f) => f.fixId)).toContain("fix-0000");
    expect(doc.locationHistory.map((f) => f.fixId)).toContain("fix-0500");
  });

  it("geofence events: internally exhausts HistoryStore's cursor pagination (501 events on one day, above the 500 internal page size)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    for (let i = 0; i < 501; i++) {
      const minute = String(i % 60).padStart(2, "0");
      const hour = String(Math.floor(i / 60)).padStart(2, "0");
      await deps.historyStore.appendEvent(FAMILY_ID, {
        eventId: `evt-${String(i).padStart(4, "0")}`,
        userId: MEMBER_ID,
        deviceId: "device-2a",
        geofenceId: "gf_home",
        geofenceName: "Home",
        lat: 51.0543,
        lon: 3.7174,
        radiusM: 150,
        transition: "enter",
        recordedAt: `2026-07-24T${hour}:${minute}:00Z`,
        receivedAt: `2026-07-24T${hour}:${minute}:02Z`,
      });
    }

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.geofenceEvents).toHaveLength(501);
    expect(doc.geofenceEvents.map((e) => e.eventId)).toContain("evt-0000");
    expect(doc.geofenceEvents.map((e) => e.eventId)).toContain("evt-0500");
  });

  it("geofence events: only the subject's own lines, never another member's", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.historyStore.appendEvent(FAMILY_ID, {
      eventId: "evt-mine",
      userId: MEMBER_ID,
      deviceId: "device-2a",
      geofenceId: "gf_home",
      geofenceName: "Home",
      lat: 51.0543,
      lon: 3.7174,
      radiusM: 150,
      transition: "enter",
      recordedAt: "2026-07-24T09:00:00Z",
      receivedAt: "2026-07-24T09:00:02Z",
    });
    await deps.historyStore.appendEvent(FAMILY_ID, {
      eventId: "evt-not-mine",
      userId: PARENT_ID,
      deviceId: "device-parent",
      geofenceId: "gf_home",
      geofenceName: "Home",
      lat: 51.0543,
      lon: 3.7174,
      radiusM: 150,
      transition: "exit",
      recordedAt: "2026-07-24T10:00:00Z",
      receivedAt: "2026-07-24T10:00:02Z",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.geofenceEvents.map((e) => e.eventId)).toEqual(["evt-mine"]);
  });

  it("usage: uid-keyed rows present for a family-less subject", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile("solo", { familyId: null, role: null, displayName: "Solo" });
    await deps.usageRepo.increment("solo", "apiCalls", "2026-07-24", 41);

    const doc = await exportUserData({ uid: "solo", familyId: null, role: null, query: {} }, deps);

    expect(doc.usage).toEqual([{ date: "2026-07-24", metric: "apiCalls", count: 41 }]);
  });

  it("usage: family-keyed rows are ABSENT for a family member (household aggregate, not subject-scoped)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.usageRepo.increment(FAMILY_ID, "apiCalls", "2026-07-24", 41);
    await deps.usageRepo.increment(FAMILY_ID, "locationBatches", "2026-07-24", 7);

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.usage).toEqual([]);
  });

  it("usage: the subjectFamilyId gate stays closed for a family member even if a stray uid-keyed row exists under their own uid", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // Not a normal state (001 §9 keys every metric family-wide for a family member) — proves
    // the gate itself, not merely the absence of data that would never be written this way.
    await deps.usageRepo.increment(MEMBER_ID, "apiCalls", "2026-07-24", 5);

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.usage).toEqual([]);
  });

  it("groups: includes an active membership with own per-group displayName/role/joinedAt and own position", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.groupRepo.createGroupMeta({
      groupId: "grp_1234567890123456789",
      name: "Festival crew",
      ownerUserId: PARENT_ID,
      createdAt: "2026-07-20T00:00:00Z",
      endsAt: "2026-08-01T00:00:00Z",
      expiryPolicy: "delete",
      code: "ABCD1234",
    });
    await deps.groupRepo.addMember("grp_1234567890123456789", {
      userId: MEMBER_ID,
      role: "member",
      displayName: "Noor F.",
      joinedAt: "2026-07-20T10:00:00Z",
    });
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_1234567890123456789",
      role: "member",
      joinedAt: "2026-07-20T10:00:00Z",
    });
    deps.groupLastKnownRepo.seed("grp_1234567890123456789", {
      userId: MEMBER_ID,
      lat: 51.2,
      lon: 3.3,
      accuracyM: 20,
      recordedAt: "2026-07-25T10:00:00Z",
      receivedAt: "2026-07-25T10:00:02Z",
      syncIntervalMinutes: 15,
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groups).toEqual([
      {
        groupId: "grp_1234567890123456789",
        name: "Festival crew",
        role: "member",
        displayName: "Noor F.",
        joinedAt: "2026-07-20T10:00:00Z",
        state: "active",
        endsAt: "2026-08-01T00:00:00Z",
      },
    ]);
    expect(doc.groupPositions).toEqual([
      { groupId: "grp_1234567890123456789", lat: 51.2, lon: 3.3, accuracyM: 20, recordedAt: "2026-07-25T10:00:00Z" },
    ]);
  });

  it("groups: skips an orphaned reverse-index row (group meta already gone — self-healing, same as listGroups.ts)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_gone00000000000000",
      role: "member",
      joinedAt: "2026-07-01T00:00:00Z",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groups).toEqual([]);
    expect(doc.groupPositions).toEqual([]);
  });

  it("groups: excludes an expired (delete-policy, past endsAt) group — never serialized (005 §2.2)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.groupRepo.createGroupMeta({
      groupId: "grp_expired000000000000",
      name: "Old trip",
      ownerUserId: MEMBER_ID,
      createdAt: "2026-01-01T00:00:00Z",
      endsAt: "2026-01-10T00:00:00Z", // long past NOW, policy=delete -> expired
      expiryPolicy: "delete",
      code: "OLDX0001",
    });
    await deps.groupRepo.addMember("grp_expired000000000000", {
      userId: MEMBER_ID,
      role: "owner",
      displayName: "Noor",
      joinedAt: "2026-01-01T00:00:00Z",
    });
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_expired000000000000",
      role: "owner",
      joinedAt: "2026-01-01T00:00:00Z",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groups).toEqual([]);
  });

  it("groups: skips when only the meta row is gone but the member row still exists (crash-mid-sweep, same defense-in-depth as getGroupDetail)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.groupRepo.createGroupMeta({
      groupId: "grp_crashmeta0000000000",
      name: "Crashed",
      ownerUserId: MEMBER_ID,
      createdAt: "2026-07-01T00:00:00Z",
      endsAt: "2026-08-01T00:00:00Z",
      expiryPolicy: "delete",
      code: "CRASH001",
    });
    await deps.groupRepo.addMember("grp_crashmeta0000000000", {
      userId: MEMBER_ID,
      role: "owner",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_crashmeta0000000000",
      role: "owner",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.groupRepo.deleteMetaOnlyForTest("grp_crashmeta0000000000");

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groups).toEqual([]);
    expect(doc.groupPositions).toEqual([]);
  });

  it("groups: skips when the reverse index claims membership but the roster row is missing (self-healing)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.groupRepo.createGroupMeta({
      groupId: "grp_noroster00000000000",
      name: "No roster row",
      ownerUserId: PARENT_ID,
      createdAt: "2026-07-01T00:00:00Z",
      endsAt: "2026-08-01T00:00:00Z",
      expiryPolicy: "delete",
      code: "NOROW001",
    });
    // Deliberately no groupRepo.addMember(...) for MEMBER_ID — only the reverse index claims it.
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_noroster00000000000",
      role: "member",
      joinedAt: "2026-07-01T00:00:00Z",
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groups).toEqual([]);
  });

  it("groupPositions: selects the subject's own row when multiple members have reported a position", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.groupRepo.createGroupMeta({
      groupId: "grp_multipos0000000000",
      name: "Crew",
      ownerUserId: PARENT_ID,
      createdAt: "2026-07-01T00:00:00Z",
      endsAt: "2026-08-01T00:00:00Z",
      expiryPolicy: "delete",
      code: "MULTI001",
    });
    await deps.groupRepo.addMember("grp_multipos0000000000", {
      userId: MEMBER_ID,
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_multipos0000000000",
      role: "member",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Seeded FIRST (insertion order) so a naive "first row" bug would pick this one instead.
    deps.groupLastKnownRepo.seed("grp_multipos0000000000", {
      userId: PARENT_ID,
      lat: 0,
      lon: 0,
      accuracyM: 5,
      recordedAt: "2026-07-25T08:00:00Z",
      receivedAt: "2026-07-25T08:00:02Z",
      syncIntervalMinutes: 15,
    });
    deps.groupLastKnownRepo.seed("grp_multipos0000000000", {
      userId: MEMBER_ID,
      lat: 51.2,
      lon: 3.3,
      accuracyM: 20,
      recordedAt: "2026-07-25T10:00:00Z",
      receivedAt: "2026-07-25T10:00:02Z",
      syncIntervalMinutes: 15,
    });

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groupPositions).toEqual([
      {
        groupId: "grp_multipos0000000000",
        lat: 51.2,
        lon: 3.3,
        accuracyM: 20,
        recordedAt: "2026-07-25T10:00:00Z",
      },
    ]);
  });

  it("groupPositions: omits an active membership that has not reported a position in-group yet", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await deps.groupRepo.createGroupMeta({
      groupId: "grp_noposition00000000",
      name: "Fresh join",
      ownerUserId: PARENT_ID,
      createdAt: "2026-07-01T00:00:00Z",
      endsAt: "2026-08-01T00:00:00Z",
      expiryPolicy: "delete",
      code: "NOPOS0001",
    });
    await deps.groupRepo.addMember("grp_noposition00000000", {
      userId: MEMBER_ID,
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.userRepo.addGroupMembership(MEMBER_ID, {
      groupId: "grp_noposition00000000",
      role: "member",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Deliberately no groupLastKnownRepo.seed(...) — the member has not reported yet.

    const doc = await exportUserData(
      { uid: MEMBER_ID, familyId: FAMILY_ID, role: "member", query: {} },
      deps,
    );

    expect(doc.groups).toHaveLength(1);
    expect(doc.groupPositions).toEqual([]);
  });
});
