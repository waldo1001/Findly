import { describe, expect, it } from "vitest";
import { patchDeviceSettings } from "../../../src/domain/device/patchDeviceSettings";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FakePushSender } from "../../fakes/fakePushSender";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    entitlementsRepo,
    pushSender: new FakePushSender(),
  };
}

// specs/002 §2.4 (B8 re-key) — Devices are keyed by ownerUserId, never familyId. Seeds
// under the record's own ownerUserId partition (defaulting to "u1").
function seedDevice(deps: ReturnType<typeof buildDeps>, overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  const device: DeviceRecord = {
    deviceId: DEVICE_ID,
    ownerUserId: "u1",
    platform: "android",
    model: "Pixel",
    appVersion: "1.0.0",
    deviceName: "Pixel",
    pushToken: "existing-token",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  };
  deps.deviceRepo.seed(device.ownerUserId, device);
  return device;
}

async function seedFamily(deps: ReturnType<typeof buildDeps>): Promise<void> {
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
}

describe("domain/device/patchDeviceSettings", () => {
  it("a parent may update any field of any family member's device, found by fanning out across the family's per-owner partitions (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2" });

    const result = await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 30, trackingEnabled: false, deviceName: "Noor's tablet" },
      },
      deps,
    );

    expect(result.device).toMatchObject({
      syncIntervalMinutes: 30,
      trackingEnabled: false,
      deviceName: "Noor's tablet",
    });
    // Written back into the DEVICE OWNER's own partition, not the caller's.
    const stored = await deps.deviceRepo.getDevice("u2", DEVICE_ID);
    expect(stored?.syncIntervalMinutes).toBe(30);
  });

  it("sends a SETTINGS_CHANGED push carrying the full current state when syncIntervalMinutes/trackingEnabled actually change", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", syncIntervalMinutes: 15, trackingEnabled: true });

    await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 30, trackingEnabled: false },
      },
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(1);
    expect(deps.pushSender.sent[0]).toMatchObject({
      token: "device-token",
      type: "SETTINGS_CHANGED",
      data: { type: "SETTINGS_CHANGED", syncIntervalMinutes: "30", trackingEnabled: "false" },
    });
  });

  it("sends a push when only trackingEnabled changes (syncIntervalMinutes untouched)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", syncIntervalMinutes: 15, trackingEnabled: true });

    await patchDeviceSettings(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { trackingEnabled: false } },
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(1);
    expect(deps.pushSender.sent[0]?.data).toMatchObject({ syncIntervalMinutes: "15", trackingEnabled: "false" });
  });

  it("leaves pushInvalid false after a successful (non-invalidToken) push", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", pushInvalid: false, syncIntervalMinutes: 15 });

    await patchDeviceSettings(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { syncIntervalMinutes: 30 } },
      deps,
    );

    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushInvalid).toBe(false);
  });

  it("sends no push when neither syncIntervalMinutes nor trackingEnabled actually changed", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", syncIntervalMinutes: 15, trackingEnabled: true });

    await patchDeviceSettings(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { deviceName: "New name" } },
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("sends no push when the new values equal the ones already stored (no real change)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", syncIntervalMinutes: 30, trackingEnabled: true });

    await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 30, trackingEnabled: true },
      },
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("sends no push when the device has no pushToken", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: undefined, syncIntervalMinutes: 15 });

    await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 30 },
      },
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("sends no push when the device's pushToken is already marked invalid", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", pushInvalid: true, syncIntervalMinutes: 15 });

    await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 30 },
      },
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("marks the device pushInvalid on an invalidToken push outcome (§8.5 hygiene)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "device-token", syncIntervalMinutes: 15 });
    deps.pushSender.setOutcome("invalidToken");

    await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 30 },
      },
      deps,
    );

    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushInvalid).toBe(true);
  });

  it("a non-parent owner may update only pushToken on their own device", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });

    const result = await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "member",
        deviceId: DEVICE_ID,
        body: { pushToken: "fresh-token" },
      },
      deps,
    );

    expect(result.device.deviceId).toBe(DEVICE_ID);
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushToken).toBe("fresh-token");
  });

  it("throws AUTH_FORBIDDEN when a non-parent owner attempts syncIntervalMinutes", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });

    await expectAppError(
      patchDeviceSettings(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          role: "member",
          deviceId: DEVICE_ID,
          body: { syncIntervalMinutes: 30 },
        },
        deps,
      ),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws AUTH_FORBIDDEN when a non-parent owner attempts trackingEnabled (isolated from other restricted fields)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID, body: { trackingEnabled: false } },
        deps,
      ),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws AUTH_FORBIDDEN when a non-parent owner attempts deviceName (isolated from other restricted fields)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID, body: { deviceName: "New name" } },
        deps,
      ),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws AUTH_FORBIDDEN when a non-parent, non-owner member targets someone else's device (found via family fan-out, 002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2" });

    await expectAppError(
      patchDeviceSettings(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          role: "member",
          deviceId: DEVICE_ID,
          body: { pushToken: "fresh-token" },
        },
        deps,
      ),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws DEVICE_NOT_FOUND when a non-parent member references a deviceId that belongs to no one in their family (fan-out finds nothing, not just AUTH_FORBIDDEN masking)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // Seeded under a stranger who is NOT a member of this family — fan-out must not find it.
    seedDevice(deps, { ownerUserId: "stranger" });

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID, body: { pushToken: "x" } },
        deps,
      ),
      "DEVICE_NOT_FOUND",
    );
  });

  it("a family-less owner may update any field of their own device (§4.3 family-less allowance)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u3" });

    const result = await patchDeviceSettings(
      {
        uid: "u3",
        familyId: null,
        role: null,
        deviceId: DEVICE_ID,
        body: { syncIntervalMinutes: 60, trackingEnabled: false, deviceName: "Sam's phone" },
      },
      deps,
    );

    expect(result.device).toMatchObject({
      syncIntervalMinutes: 60,
      trackingEnabled: false,
      deviceName: "Sam's phone",
    });
    expect(result.features.subscriptionStatus).toBe("free");
  });

  it("throws DEVICE_NOT_FOUND for an unknown deviceId", async () => {
    const deps = buildDeps();

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { trackingEnabled: false } },
        deps,
      ),
      "DEVICE_NOT_FOUND",
    );
  });

  it("throws DEVICE_NOT_FOUND when a family-less caller references a deviceId outside their own partition (no fan-out without a family)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "someone-else" });

    await expectAppError(
      patchDeviceSettings(
        { uid: "u3", familyId: null, role: null, deviceId: DEVICE_ID, body: { trackingEnabled: false } },
        deps,
      ),
      "DEVICE_NOT_FOUND",
    );
  });

  it('throws VALIDATION_FAILED with details.fields: ["syncIntervalMinutes"] for a value outside the allowed set', async () => {
    const deps = buildDeps();
    seedDevice(deps, {});

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { syncIntervalMinutes: 20 } },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["syncIntervalMinutes"] },
    );
  });

  it("throws VALIDATION_FAILED when the body has no fields at all", async () => {
    const deps = buildDeps();
    seedDevice(deps, {});

    await expectAppError(
      patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: {} }, deps),
      "VALIDATION_FAILED",
    );
  });

  it("accepts syncIntervalMinutes at the plan floor boundary (5, minSyncIntervalMinutes, §1.4/§9)", async () => {
    const deps = buildDeps();
    seedDevice(deps, {});

    const result = await patchDeviceSettings(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { syncIntervalMinutes: 5 } },
      deps,
    );

    expect(result.device.syncIntervalMinutes).toBe(5);
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deviceRepo = new InMemoryDeviceRepo();
    const familyRepo = new InMemoryFamilyRepo();
    const entitlementsRepo = new InMemoryEntitlementsRepo(); // deliberately not seeded
    const pushSender = new FakePushSender();
    deviceRepo.seed("u1", {
      deviceId: DEVICE_ID,
      ownerUserId: "u1",
      platform: "android",
      model: "Pixel",
      appVersion: "1.0.0",
      deviceName: "Pixel",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { trackingEnabled: false } },
        { deviceRepo, familyRepo, entitlementsRepo, pushSender },
      ),
      "INTERNAL_ERROR",
    );
  });

  it("never leaks pushToken/locationPushToken in the response (write-only, §4.1)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { pushToken: "secret", locationPushToken: "secret-loc" });

    const result = await patchDeviceSettings(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        role: "parent",
        deviceId: DEVICE_ID,
        body: { pushToken: "new-secret" },
      },
      deps,
    );

    expect(result.device).not.toHaveProperty("pushToken");
    expect(result.device).not.toHaveProperty("locationPushToken");
  });

  it("preserves fields not present in the patch body", async () => {
    const deps = buildDeps();
    seedDevice(deps, { model: "Pixel 8", appVersion: "1.0.0", deviceName: "Eric's phone" });

    const result = await patchDeviceSettings(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { trackingEnabled: false } },
      deps,
    );

    expect(result.device).toMatchObject({ model: "Pixel 8", appVersion: "1.0.0", deviceName: "Eric's phone" });
  });

  it("preserves a truthy trackingEnabled when the patch body omits it", async () => {
    const deps = buildDeps();
    seedDevice(deps, { trackingEnabled: true });

    const result = await patchDeviceSettings(
      { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { deviceName: "New name" } },
      deps,
    );

    expect(result.device.trackingEnabled).toBe(true);
  });

  // specs/001 §4.3, 011 §4.4/§5 — staleNudgeEnabled is owner-only in every role.
  it("a member owner may set staleNudgeEnabled on their own device", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2" });

    const result = await patchDeviceSettings({ uid: "u2", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID, body: { staleNudgeEnabled: false } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(false);
    expect((await deps.deviceRepo.getDevice("u2", DEVICE_ID))?.staleNudgeEnabled).toBe(false);
  });

  it("a parent owner may set staleNudgeEnabled on their own device, and back to true", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u1", staleNudgeEnabled: false });

    const result = await patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { staleNudgeEnabled: true } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(true);
  });

  it("a family-less owner may set staleNudgeEnabled on their own device", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u9" });

    const result = await patchDeviceSettings({ uid: "u9", familyId: null, role: null, deviceId: DEVICE_ID, body: { staleNudgeEnabled: false } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(false);
  });

  it("a PARENT setting staleNudgeEnabled on another member's device gets AUTH_FORBIDDEN and nothing is written", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2" });

    await expectAppError(patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { staleNudgeEnabled: false } }, deps), "AUTH_FORBIDDEN");
    expect((await deps.deviceRepo.getDevice("u2", DEVICE_ID))?.staleNudgeEnabled).toBeUndefined();
  });

  it("a parent mixing staleNudgeEnabled with other fields on another member's device is rejected as a whole", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2" });

    await expectAppError(patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { trackingEnabled: false, staleNudgeEnabled: false } }, deps), "AUTH_FORBIDDEN");
    expect((await deps.deviceRepo.getDevice("u2", DEVICE_ID))?.trackingEnabled).toBe(true);
  });

  it("a parent can still change other fields on another member's device without touching staleNudgeEnabled", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2", staleNudgeEnabled: false });

    const result = await patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { deviceName: "Renamed" } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(false);
  });

  it("a non-boolean staleNudgeEnabled is VALIDATION_FAILED", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });

    await expectAppError(patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { staleNudgeEnabled: "no" } }, deps), "VALIDATION_FAILED", { fields: ["staleNudgeEnabled"] });
  });

  it("staleNudgeEnabled alone is a valid patch, sends NO SETTINGS_CHANGED push and leaves other settings alone", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1", pushToken: "device-token", syncIntervalMinutes: 15, trackingEnabled: true });

    await patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { staleNudgeEnabled: false } }, deps);

    expect(deps.pushSender.sent).toHaveLength(0);
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored).toMatchObject({ syncIntervalMinutes: 15, trackingEnabled: true, deviceName: "Pixel" });
  });

  it("an other-field patch preserves the stored staleNudgeEnabled and lastNudgedAt", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1", staleNudgeEnabled: false, lastNudgedAt: "2026-07-18T10:00:00Z" });

    await patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { trackingEnabled: false } }, deps);

    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored).toMatchObject({ staleNudgeEnabled: false, lastNudgedAt: "2026-07-18T10:00:00Z" });
  });

  it("a patch of a legacy row (no staleNudgeEnabled property) reports true", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });

    const result = await patchDeviceSettings({ uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { deviceName: "x" } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(true);
  });

  // PATCH-vs-DELETE race (001 §4.4): a PATCH that read the device before a concurrent
  // removal must not resurrect it by writing the row back.
  it("a device removed between the PATCH's read and its write is DEVICE_NOT_FOUND and is NOT resurrected", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "u1" });
    const realGet = deps.deviceRepo.getDevice.bind(deps.deviceRepo);
    deps.deviceRepo.getDevice = async (owner, id) => {
      const found = await realGet(owner, id);
      await deps.deviceRepo.deleteDevice(owner, id); // concurrent DELETE lands right after the read
      return found;
    };

    await expectAppError(
      patchDeviceSettings(
        { uid: "u1", familyId: FAMILY_ID, role: "parent", deviceId: DEVICE_ID, body: { deviceName: "x" } },
        deps,
      ),
      "DEVICE_NOT_FOUND",
    );
    expect(await realGet("u1", DEVICE_ID)).toBeNull();
  });

  it("an owner-only PATCH (pushToken) message for a forbidden field mentions staleNudgeEnabled", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedDevice(deps, { ownerUserId: "u2" });

    await expect(
      patchDeviceSettings(
        { uid: "u2", familyId: FAMILY_ID, role: "member", deviceId: DEVICE_ID, body: { deviceName: "x" } },
        deps,
      ),
    ).rejects.toMatchObject({ code: "AUTH_FORBIDDEN", message: expect.stringContaining("staleNudgeEnabled") });
  });
});
