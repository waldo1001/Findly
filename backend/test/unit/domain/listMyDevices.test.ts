import { describe, expect, it } from "vitest";
import { listMyDevices } from "../../../src/domain/device/listMyDevices";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";

function buildDeps() {
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    userRepo: new InMemoryUserRepo(),
    entitlementsRepo: new InMemoryEntitlementsRepo(),
    clock: new FixedClock(new Date("2026-07-19T09:30:00Z")),
  };
}

function baseDevice(overrides: Partial<DeviceRecord>): DeviceRecord {
  return {
    deviceId: "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b",
    ownerUserId: "u1",
    platform: "android",
    model: "Pixel",
    appVersion: "1.0.0",
    deviceName: "Pixel",
    pushToken: "some-token",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    ...overrides,
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
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: "u2",
    role: "member",
    displayName: "Noor",
    joinedAt: "2026-07-19T08:30:00Z",
  });
  deps.entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
}

describe("domain/device/listMyDevices", () => {
  it("lists every family member's devices with ownerDisplayName + lastSeenAt (§4.2 open-family shape, fanned out per-member per 002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u1", baseDevice({ deviceId: "device-1", ownerUserId: "u1" }));
    deps.deviceRepo.seed("u2", baseDevice({ deviceId: "device-2", ownerUserId: "u2", model: "iPhone" }));

    const result = await listMyDevices({ uid: "u1", familyId: FAMILY_ID }, deps);

    expect(result.devices).toHaveLength(2);
    expect(result.devices).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ deviceId: "device-1", ownerUserId: "u1", ownerDisplayName: "Eric" }),
        expect.objectContaining({ deviceId: "device-2", ownerUserId: "u2", ownerDisplayName: "Noor" }),
      ]),
    );
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("never leaks pushToken/locationPushToken in the response (write-only, §4.1)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(
      "u1",
      baseDevice({ deviceId: "device-1", ownerUserId: "u1", pushToken: "secret-token", locationPushToken: "secret-loc" }),
    );

    const result = await listMyDevices({ uid: "u1", familyId: FAMILY_ID }, deps);

    expect(result.devices[0]).not.toHaveProperty("pushToken");
    expect(result.devices[0]).not.toHaveProperty("locationPushToken");
  });

  it("does not leak one member's devices into another family's listing (per-owner partition isolation, 002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // A device registered to some unrelated user who is NOT in this family — must never
    // appear, since fan-out only ever visits THIS family's roster partitions.
    deps.deviceRepo.seed("stranger", baseDevice({ deviceId: "stranger-device", ownerUserId: "stranger" }));
    deps.deviceRepo.seed("u1", baseDevice({ deviceId: "device-1", ownerUserId: "u1" }));

    const result = await listMyDevices({ uid: "u1", familyId: FAMILY_ID }, deps);

    expect(result.devices.map((d) => d.deviceId)).toEqual(["device-1"]);
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deviceRepo = new InMemoryDeviceRepo();
    const familyRepo = new InMemoryFamilyRepo();
    await familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: "u1",
      createdAt: "2026-07-19T08:00:00Z",
    });
    const userRepo = new InMemoryUserRepo();
    const entitlementsRepo = new InMemoryEntitlementsRepo(); // deliberately not seeded

    await expectAppError(
      listMyDevices({ uid: "u1", familyId: FAMILY_ID }, { deviceRepo, familyRepo, userRepo, entitlementsRepo }),
      "INTERNAL_ERROR",
    );
  });

  it("returns only the caller's own devices for a family-less caller (§4.2 family-less allowance)", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile("u3", { familyId: null, role: null, displayName: "Group-only Sam" });
    deps.deviceRepo.seed("u3", baseDevice({ deviceId: "device-3", ownerUserId: "u3" }));

    const result = await listMyDevices({ uid: "u3", familyId: null }, deps);

    expect(result.devices).toHaveLength(1);
    expect(result.devices[0]).toMatchObject({
      deviceId: "device-3",
      ownerUserId: "u3",
      ownerDisplayName: "Group-only Sam",
    });
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("returns an empty devices array for a family-less caller with no devices yet", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile("u3", { familyId: null, role: null, displayName: "Group-only Sam" });

    const result = await listMyDevices({ uid: "u3", familyId: null }, deps);

    expect(result.devices).toEqual([]);
  });

  it("falls back to the caller's uid as ownerDisplayName when the profile lookup returns null (data-integrity edge case)", async () => {
    const deps = buildDeps();
    // Deliberately no userRepo.createProfile call — getProfile(uid) resolves null even
    // though authGuard already let the request through (defense in depth, not a real path).
    deps.deviceRepo.seed("u3", baseDevice({ deviceId: "device-3", ownerUserId: "u3" }));

    const result = await listMyDevices({ uid: "u3", familyId: null }, deps);

    expect(result.devices[0]?.ownerDisplayName).toBe("u3");
  });

  it("includes staleNudgeEnabled (false when stored false, true when absent) and never lastNudgedAt", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u1", baseDevice({ deviceId: "device-1", ownerUserId: "u1", staleNudgeEnabled: false, lastNudgedAt: "2026-07-18T10:00:00Z" }));
    deps.deviceRepo.seed("u2", baseDevice({ deviceId: "device-2", ownerUserId: "u2" }));

    const result = await listMyDevices({ uid: "u1", familyId: FAMILY_ID }, deps);

    const byId = new Map(result.devices.map((d) => [d.deviceId, d]));
    expect(byId.get("device-1")?.staleNudgeEnabled).toBe(false);
    expect(byId.get("device-2")?.staleNudgeEnabled).toBe(true);
    expect(byId.get("device-1")).not.toHaveProperty("lastNudgedAt");
  });

  // 001 §4.2 (corrected 2026-10-07) — isDormant on every listed device, same rule as §5.2.
  it("family listing: isDormant is a boolean on every device, false at exactly 30 days and true just past it", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    const nowMs = new Date("2026-07-19T09:30:00Z").getTime();
    const day = 24 * 60 * 60 * 1000;
    deps.deviceRepo.seed("u1", baseDevice({ deviceId: "fresh", ownerUserId: "u1" }));
    deps.deviceRepo.seed("u2", baseDevice({ deviceId: "edge", ownerUserId: "u2", lastSeenAt: new Date(nowMs - 30 * day).toISOString() }));
    deps.deviceRepo.seed("u2", baseDevice({ deviceId: "over", ownerUserId: "u2", lastSeenAt: new Date(nowMs - 30 * day - 1).toISOString() }));

    const result = await listMyDevices({ uid: "u1", familyId: FAMILY_ID }, deps);

    const byId = new Map(result.devices.map((d) => [d.deviceId, d]));
    expect(byId.get("fresh")?.isDormant).toBe(false);
    expect(byId.get("edge")?.isDormant).toBe(false);
    expect(byId.get("over")?.isDormant).toBe(true);
  });

  it("family-less own-devices listing: isDormant present, with the registeredAt fallback when lastSeenAt is absent", async () => {
    const deps = buildDeps();
    await deps.userRepo.createProfile("u3", { familyId: null, role: null, displayName: "Sam" });
    deps.deviceRepo.seed("u3", baseDevice({ deviceId: "d-old", ownerUserId: "u3", lastSeenAt: "2026-05-01T00:00:00Z" }));
    deps.deviceRepo.seed(
      "u3",
      baseDevice({ deviceId: "d-nolastseen", ownerUserId: "u3", registeredAt: "2026-07-10T00:00:00Z", lastSeenAt: undefined as unknown as string }),
    );
    deps.deviceRepo.seed("u3", baseDevice({ deviceId: "d-new", ownerUserId: "u3" }));

    const result = await listMyDevices({ uid: "u3", familyId: null }, deps);

    const byId = new Map(result.devices.map((d) => [d.deviceId, d]));
    expect(byId.get("d-old")?.isDormant).toBe(true);
    expect(byId.get("d-nolastseen")?.isDormant).toBe(false);
    expect(byId.get("d-new")?.isDormant).toBe(false);
  });
});
