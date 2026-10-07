import { describe, expect, it } from "vitest";
import { latestLocations } from "../../../src/domain/location/latestLocations";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const NOW = "2026-07-19T09:30:00Z";

function device(overrides: Partial<DeviceRecord>): DeviceRecord {
  return {
    deviceId: "device-1",
    ownerUserId: "u1",
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Eric's phone",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  };
}

async function buildDeps() {
  const familyRepo = new InMemoryFamilyRepo();
  await familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: "u1",
    createdAt: "2026-07-01T00:00:00Z",
  });
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  return {
    familyRepo,
    deviceRepo: new InMemoryDeviceRepo(),
    lastKnownRepo: new InMemoryLastKnownRepo(),
    entitlementsRepo,
    clock: new FixedClock(new Date(NOW)),
  };
}

describe("domain/location/latestLocations", () => {
  it("includes every member, even one with no registered devices (devices: [])", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u4",
      role: "member",
      displayName: "DeviceLess",
      joinedAt: "2026-07-01T00:00:00Z",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const deviceLess = result.members.find((m) => m.userId === "u4");
    expect(deviceLess).toEqual({ userId: "u4", displayName: "DeviceLess", devices: [] });
  });

  it("includes a never-reported device with lat/lon/recordedAt/isStale all null", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u2",
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed("u2", device({ deviceId: "d2", ownerUserId: "u2", deviceName: "Noor's phone" }));

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const noor = result.members.find((m) => m.userId === "u2");
    expect(noor?.devices).toEqual([
      {
        deviceId: "d2",
        deviceName: "Noor's phone",
        lat: null,
        lon: null,
        accuracyM: null,
        recordedAt: null,
        receivedAt: null,
        batteryPct: null,
        source: null,
        trackingEnabled: true,
        syncIntervalMinutes: 15,
        isStale: null,
        isDormant: false,
      },
    ]);
  });

  it("reports a fresh device's last-known fix with isStale computed from now - recordedAt", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed("u1", device({ deviceId: "d1", ownerUserId: "u1", syncIntervalMinutes: 15 }));
    deps.lastKnownRepo.seed("u1", {
      deviceId: "d1",
      lat: 51.0543,
      lon: 3.7174,
      accuracyM: 15.0,
      batteryPct: 78,
      recordedAt: "2026-07-19T09:05:00Z", // 25 min before NOW; threshold 2*15=30min -> not stale
      receivedAt: "2026-07-19T09:05:02Z",
      source: "periodic",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const eric = result.members.find((m) => m.userId === "u1");
    expect(eric?.devices).toEqual([
      {
        deviceId: "d1",
        deviceName: "Eric's phone",
        lat: 51.0543,
        lon: 3.7174,
        accuracyM: 15.0,
        recordedAt: "2026-07-19T09:05:00Z",
        receivedAt: "2026-07-19T09:05:02Z",
        batteryPct: 78,
        source: "periodic",
        trackingEnabled: true,
        syncIntervalMinutes: 15,
        isStale: false,
        isDormant: false,
      },
    ]);
  });

  it("isStale formula: exactly 2x syncIntervalMinutes old is NOT stale (strict >)", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed("u1", device({ deviceId: "d1", ownerUserId: "u1", syncIntervalMinutes: 15 }));
    deps.lastKnownRepo.seed("u1", {
      deviceId: "d1",
      lat: 51.0,
      lon: 3.7,
      accuracyM: 10,
      batteryPct: 50,
      recordedAt: "2026-07-19T09:00:00Z", // exactly 30 min before NOW (2 * 15)
      receivedAt: "2026-07-19T09:00:01Z",
      source: "periodic",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const device1 = result.members.find((m) => m.userId === "u1")?.devices[0];
    expect(device1?.isStale).toBe(false);
  });

  it("isStale formula: one minute past 2x syncIntervalMinutes IS stale", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed("u1", device({ deviceId: "d1", ownerUserId: "u1", syncIntervalMinutes: 15 }));
    deps.lastKnownRepo.seed("u1", {
      deviceId: "d1",
      lat: 51.0,
      lon: 3.7,
      accuracyM: 10,
      batteryPct: 50,
      recordedAt: "2026-07-19T08:59:00Z", // 31 min before NOW (> 2 * 15)
      receivedAt: "2026-07-19T08:59:01Z",
      source: "periodic",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const device1 = result.members.find((m) => m.userId === "u1")?.devices[0];
    expect(device1?.isStale).toBe(true);
  });

  it("joins multiple devices for the same member correctly", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed("u1", device({ deviceId: "d1", ownerUserId: "u1" }));
    deps.deviceRepo.seed("u1", device({ deviceId: "d2", ownerUserId: "u1", deviceName: "Eric's tablet" }));

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const eric = result.members.find((m) => m.userId === "u1");
    expect(eric?.devices.map((d) => d.deviceId).sort()).toEqual(["d1", "d2"]);
  });

  it("fans out devices AND last-knowns per-member across per-owner partitions, not a single shared family partition (002 §2.4/§2.5)", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u2",
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed("u1", device({ deviceId: "d1", ownerUserId: "u1" }));
    deps.deviceRepo.seed("u2", device({ deviceId: "d2", ownerUserId: "u2", deviceName: "Noor's phone" }));
    deps.lastKnownRepo.seed("u1", {
      deviceId: "d1",
      lat: 1,
      lon: 1,
      accuracyM: 5,
      batteryPct: 50,
      recordedAt: "2026-07-19T09:20:00Z",
      receivedAt: "2026-07-19T09:20:01Z",
      source: "periodic",
    });
    deps.lastKnownRepo.seed("u2", {
      deviceId: "d2",
      lat: 2,
      lon: 2,
      accuracyM: 5,
      batteryPct: 60,
      recordedAt: "2026-07-19T09:25:00Z",
      receivedAt: "2026-07-19T09:25:01Z",
      source: "periodic",
    });
    // A device+last-known pair belonging to a stranger outside this family entirely — must
    // never be picked up, since fan-out only ever visits THIS family's roster partitions.
    deps.deviceRepo.seed("stranger", device({ deviceId: "d-stranger", ownerUserId: "stranger" }));
    deps.lastKnownRepo.seed("stranger", {
      deviceId: "d-stranger",
      lat: 99,
      lon: 99,
      accuracyM: 5,
      batteryPct: 10,
      recordedAt: "2026-07-19T09:29:00Z",
      receivedAt: "2026-07-19T09:29:01Z",
      source: "periodic",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    expect(result.members.map((m) => m.userId).sort()).toEqual(["u1", "u2"]);
    const eric = result.members.find((m) => m.userId === "u1");
    const noor = result.members.find((m) => m.userId === "u2");
    expect(eric?.devices[0]?.lat).toBe(1);
    expect(noor?.devices[0]?.lat).toBe(2);
  });

  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = await buildDeps();

    await expectAppError(latestLocations({ familyId: null }, deps), "FAMILY_NOT_FOUND");
  });

  it("returns features derived from PLAN_MATRIX.free", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: "u1",
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    expect(result.features).toEqual(getFeatures("free"));
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const familyRepo = new InMemoryFamilyRepo();
    await familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: "u1",
      createdAt: "2026-07-01T00:00:00Z",
    });
    const deps = {
      familyRepo,
      deviceRepo: new InMemoryDeviceRepo(),
      lastKnownRepo: new InMemoryLastKnownRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
      clock: new FixedClock(new Date(NOW)),
    };

    await expectAppError(latestLocations({ familyId: FAMILY_ID }, deps), "INTERNAL_ERROR");
  });

  // specs/001 §5.2, 011 §2 — isDormant is server-computed and always a boolean.
  it("isDormant: exactly 30 days since lastSeenAt is false, one millisecond more is true", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, { userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-01T00:00:00Z" });
    const nowMs = new Date(NOW).getTime();
    const day = 24 * 60 * 60 * 1000;
    deps.deviceRepo.seed("u1", device({ deviceId: "edge", ownerUserId: "u1", lastSeenAt: new Date(nowMs - 30 * day).toISOString() }));
    deps.deviceRepo.seed("u1", device({ deviceId: "over", ownerUserId: "u1", lastSeenAt: new Date(nowMs - 30 * day - 1).toISOString() }));

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    const devices = result.members.find((m) => m.userId === "u1")?.devices ?? [];
    expect(devices.find((d) => d.deviceId === "edge")?.isDormant).toBe(false);
    expect(devices.find((d) => d.deviceId === "over")?.isDormant).toBe(true);
  });

  it("isDormant is present (true) on a never-reported dormant device whose fix fields are null", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, { userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-01T00:00:00Z" });
    deps.deviceRepo.seed("u1", device({ deviceId: "ghost", ownerUserId: "u1", lastSeenAt: "2026-05-01T00:00:00Z" }));

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    expect(result.members[0]?.devices[0]).toMatchObject({ deviceId: "ghost", lat: null, isStale: null, isDormant: true });
  });

  it("isDormant is true on a device WITH a last-known fix when the device has been silent > 30 days", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, { userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-01T00:00:00Z" });
    deps.deviceRepo.seed("u1", device({ deviceId: "old", ownerUserId: "u1", lastSeenAt: "2026-05-01T00:00:00Z" }));
    deps.lastKnownRepo.seed("u1", {
      deviceId: "old", lat: 1, lon: 2, accuracyM: 5, batteryPct: 50,
      recordedAt: "2026-05-01T00:00:00Z", receivedAt: "2026-05-01T00:00:01Z", source: "periodic",
    });

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    expect(result.members[0]?.devices[0]).toMatchObject({ isStale: true, isDormant: true });
  });

  it("isDormant falls back to registeredAt when the stored row carries no lastSeenAt", async () => {
    const deps = await buildDeps();
    await deps.familyRepo.addMember(FAMILY_ID, { userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-01T00:00:00Z" });
    deps.deviceRepo.seed(
      "u1",
      device({ deviceId: "d1", ownerUserId: "u1", registeredAt: "2026-04-01T00:00:00Z", lastSeenAt: undefined as unknown as string }),
    );

    const result = await latestLocations({ familyId: FAMILY_ID }, deps);

    expect(result.members[0]?.devices[0]?.isDormant).toBe(true);
  });
});
