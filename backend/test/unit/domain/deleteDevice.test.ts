// specs/001 §4.4, 011 §1, 002 §2.4 (removal order) — DELETE /devices/{deviceId}.
import { describe, expect, it } from "vitest";
import { deleteDevice } from "../../../src/domain/device/deleteDevice";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";
import { InMemoryIdempotencyRepo } from "../../fakes/inMemoryIdempotencyRepo";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord, LastKnownRecord, Role } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const OTHER_FAMILY_ID = "fam_ZZZZZZZZZZZZZZZZZZZZ";
const DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const SIBLING_DEVICE_ID = "11111111-2222-4333-8444-555555555555";

function buildDeps() {
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    lastKnownRepo: new InMemoryLastKnownRepo(),
    idempotencyRepo: new InMemoryIdempotencyRepo(),
  };
}
type Deps = ReturnType<typeof buildDeps>;

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: DEVICE_ID,
    ownerUserId: "u2",
    platform: "android",
    model: "Pixel",
    appVersion: "1.0.0",
    deviceName: "Noor's phone",
    pushToken: "tok",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  };
}

function fix(deviceId: string): LastKnownRecord {
  return {
    deviceId,
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    batteryPct: 80,
    recordedAt: "2026-07-19T09:00:00Z",
    receivedAt: "2026-07-19T09:00:01Z",
    source: "periodic",
  };
}

async function seedFamily(
  deps: Deps,
  familyId = FAMILY_ID,
  members: [string, Role][] = [
    ["u1", "parent"],
    ["u2", "member"],
    ["u3", "member"],
  ],
) {
  await deps.familyRepo.createFamily({ familyId, familyName: "W", createdBy: "u1", createdAt: "2026-07-01T00:00:00Z" });
  for (const [userId, role] of members) {
    await deps.familyRepo.addMember(familyId, { userId, role, displayName: userId, joinedAt: "2026-07-01T00:00:00Z" });
  }
}

async function seedFootprint(deps: Deps, owner: string, deviceId = DEVICE_ID) {
  deps.deviceRepo.seed(owner, device({ deviceId, ownerUserId: owner }));
  deps.lastKnownRepo.seed(owner, fix(deviceId));
  await deps.idempotencyRepo.tryInsertBatchMarker(deviceId, "batch-1", { receivedAt: "2026-07-19T09:00:01Z", fixCount: 1 });
  await deps.idempotencyRepo.tryInsertEventMarker(deviceId, "event-1", "2026-07-19T09:00:01Z");
  await deps.idempotencyRepo.tryInsertFixMarker(deviceId, "fix-1", "2026-07-19T09:00:01Z");
}

describe("domain/device/deleteDevice", () => {
  it("a parent removes any family member's device: Devices, LastKnown and the marker partition are gone", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");

    await deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.getDevice("u2", DEVICE_ID)).toBeNull();
    expect(await deps.lastKnownRepo.get("u2", DEVICE_ID)).toBeNull();
    expect(deps.idempotencyRepo.hasAnyMarker(DEVICE_ID)).toBe(false);
  });

  it("a member removes their own device (found in their own partition)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");

    await deleteDevice({ uid: "u2", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.getDevice("u2", DEVICE_ID)).toBeNull();
  });

  it("a parent removes their own device (own partition first)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u1");

    await deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.getDevice("u1", DEVICE_ID)).toBeNull();
  });

  it("a family-less owner removes their own device", async () => {
    const deps = buildDeps();
    await seedFootprint(deps, "u9");

    await deleteDevice({ uid: "u9", familyId: null, role: null, deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.getDevice("u9", DEVICE_ID)).toBeNull();
    expect(await deps.lastKnownRepo.get("u9", DEVICE_ID)).toBeNull();
  });

  it("a member removing another member's device gets AUTH_FORBIDDEN and nothing is deleted", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");

    await expectAppError(
      deleteDevice({ uid: "u3", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID }, deps),
      "AUTH_FORBIDDEN",
    );

    expect(await deps.deviceRepo.getDevice("u2", DEVICE_ID)).not.toBeNull();
    expect(await deps.lastKnownRepo.get("u2", DEVICE_ID)).not.toBeNull();
    expect(deps.idempotencyRepo.hasAnyMarker(DEVICE_ID)).toBe(true);
  });

  it("a family-less caller cannot reach another user's device: DEVICE_NOT_FOUND", async () => {
    const deps = buildDeps();
    await seedFootprint(deps, "u2");

    await expectAppError(
      deleteDevice({ uid: "u9", familyId: null, role: null, deviceId: DEVICE_ID }, deps),
      "DEVICE_NOT_FOUND",
    );
    expect(await deps.deviceRepo.getDevice("u2", DEVICE_ID)).not.toBeNull();
  });

  it("a parent cannot remove a device of another family: DEVICE_NOT_FOUND", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFamily(deps, OTHER_FAMILY_ID, [["x1", "parent"]]);
    await seedFootprint(deps, "x1");

    await expectAppError(
      deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps),
      "DEVICE_NOT_FOUND",
    );
    expect(await deps.deviceRepo.getDevice("x1", DEVICE_ID)).not.toBeNull();
  });

  it("an unknown deviceId is DEVICE_NOT_FOUND", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    await expectAppError(
      deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps),
      "DEVICE_NOT_FOUND",
    );
  });

  it("a second delete of the same deviceId is DEVICE_NOT_FOUND", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");
    const input = { uid: "u1", familyId: FAMILY_ID, role: "parent" as const, deviceId: DEVICE_ID };

    await deleteDevice(input, deps);

    await expectAppError(deleteDevice(input, deps), "DEVICE_NOT_FOUND");
  });

  it("touches only the addressed device: a sibling device keeps its row, LastKnown and markers", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");
    await seedFootprint(deps, "u2", SIBLING_DEVICE_ID);

    await deleteDevice({ uid: "u2", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.getDevice("u2", SIBLING_DEVICE_ID)).not.toBeNull();
    expect(await deps.lastKnownRepo.get("u2", SIBLING_DEVICE_ID)).not.toBeNull();
    expect(deps.idempotencyRepo.hasAnyMarker(SIBLING_DEVICE_ID)).toBe(true);
  });

  it("frees a slot against maxDevices (the owner's partition count drops by one)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");
    await seedFootprint(deps, "u2", SIBLING_DEVICE_ID);
    expect(await deps.deviceRepo.countDevices("u2")).toBe(2);

    await deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.countDevices("u2")).toBe(1);
  });

  it("deletes in the 002 §2.4 order: Devices row, then LastKnown, then the marker partition", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await seedFootprint(deps, "u2");
    const order: string[] = [];
    const origDevice = deps.deviceRepo.deleteDevice.bind(deps.deviceRepo);
    const origLast = deps.lastKnownRepo.delete.bind(deps.lastKnownRepo);
    const origMarkers = deps.idempotencyRepo.deletePartition.bind(deps.idempotencyRepo);
    deps.deviceRepo.deleteDevice = async (o, d) => {
      order.push("devices");
      await origDevice(o, d);
    };
    deps.lastKnownRepo.delete = async (o, d) => {
      order.push("lastKnown");
      await origLast(o, d);
    };
    deps.idempotencyRepo.deletePartition = async (d) => {
      order.push("markers");
      await origMarkers(d);
    };

    await deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps);

    expect(order).toEqual(["devices", "lastKnown", "markers"]);
  });

  it("is tolerant of a device that never reported (no LastKnown row, no markers)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u2", device());

    await deleteDevice({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID }, deps);

    expect(await deps.deviceRepo.getDevice("u2", DEVICE_ID)).toBeNull();
  });
});
