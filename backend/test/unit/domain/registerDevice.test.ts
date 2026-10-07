import { describe, expect, it } from "vitest";
import { registerDevice } from "../../../src/domain/device/registerDevice";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const OTHER_DEVICE_ID = "4f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2c";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-19T08:00:00Z" });
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    entitlementsRepo,
    clock: new FixedClock(new Date("2026-07-19T09:05:00Z")),
  };
}

// specs/002 §2.4 (B8 re-key) + specs/001 §4.1 (deviceIdInUse restored family-wide) —
// registration-time collision checks fan out across the family roster, so tests exercising
// that need an actual family + membership seeded.
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

// specs/002 §2.4 (B8 re-key) — Devices are keyed by ownerUserId, never familyId. Seeds
// under the record's own ownerUserId partition (defaulting to "u1", the usual caller).
function seedDevice(deps: ReturnType<typeof buildDeps>, overrides: Partial<Parameters<InMemoryDeviceRepo["seed"]>[1]>) {
  const device = {
    deviceId: "seed-device",
    ownerUserId: "u1",
    platform: "android" as const,
    model: "Pixel",
    appVersion: "1.0.0",
    deviceName: "Pixel",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  };
  deps.deviceRepo.seed(device.ownerUserId, device);
}

describe("domain/device/registerDevice", () => {
  it("first registration applies defaults: syncIntervalMinutes 15, trackingEnabled true, deviceName = model when omitted", async () => {
    const deps = buildDeps();

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
      },
      deps,
    );

    expect(result.created).toBe(true);
    expect(result.device).toMatchObject({
      deviceId: DEVICE_ID,
      ownerUserId: "u1",
      platform: "android",
      model: "Pixel 8",
      appVersion: "1.0.0",
      deviceName: "Pixel 8",
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      pushInvalid: false,
    });
  });

  it("upsert of an existing deviceId updates pushToken/appVersion/model/platform, preserves interval/paused/deviceName", async () => {
    const deps = buildDeps();
    seedDevice(deps, {
      deviceId: DEVICE_ID,
      model: "Pixel 8",
      deviceName: "Noor's phone",
      pushToken: "old-token",
      syncIntervalMinutes: 30,
      trackingEnabled: false,
    });

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: {
          deviceId: DEVICE_ID,
          platform: "ios",
          model: "Pixel 9",
          appVersion: "1.1.0",
          pushToken: "new-token",
        },
      },
      deps,
    );

    expect(result.created).toBe(false);
    expect(result.device).toMatchObject({
      platform: "ios",
      model: "Pixel 9",
      appVersion: "1.1.0",
      // parent-managed settings MUST NOT reset:
      syncIntervalMinutes: 30,
      trackingEnabled: false,
      deviceName: "Noor's phone",
    });
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushToken).toBe("new-token");
  });

  it("clears a previously-set pushInvalid when the upsert supplies a genuinely fresh pushToken (specs/001 §4.1/§8.5)", async () => {
    const deps = buildDeps();
    seedDevice(deps, {
      deviceId: DEVICE_ID,
      pushToken: "stale-token",
      pushInvalid: true,
    });

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: {
          deviceId: DEVICE_ID,
          platform: "android",
          model: "Pixel",
          appVersion: "1.0.0",
          pushToken: "brand-new-token",
        },
      },
      deps,
    );

    expect(result.device.pushInvalid).toBe(false);
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushInvalid).toBe(false);
    expect(stored?.pushToken).toBe("brand-new-token");
  });

  it("does NOT clear pushInvalid when the upsert re-supplies the SAME token that's already marked invalid (specs/001 §8.5 — re-registering a known-bad token must not silently clean it)", async () => {
    const deps = buildDeps();
    seedDevice(deps, {
      deviceId: DEVICE_ID,
      pushToken: "known-bad-token",
      pushInvalid: true,
    });

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: {
          deviceId: DEVICE_ID,
          platform: "android",
          model: "Pixel",
          appVersion: "1.0.0",
          pushToken: "known-bad-token",
        },
      },
      deps,
    );

    expect(result.device.pushInvalid).toBe(true);
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushInvalid).toBe(true);
  });

  it("does NOT clear pushInvalid when the upsert omits pushToken entirely (no fresh token was supplied at all, specs/001 §8.5)", async () => {
    const deps = buildDeps();
    seedDevice(deps, {
      deviceId: DEVICE_ID,
      pushToken: "known-bad-token",
      pushInvalid: true,
    });

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel", appVersion: "1.0.1" },
      },
      deps,
    );

    expect(result.device.pushInvalid).toBe(true);
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushInvalid).toBe(true);
    expect(stored?.pushToken).toBe("known-bad-token");
  });

  it("an upsert that omits pushToken/locationPushToken preserves the previously stored ones", async () => {
    const deps = buildDeps();
    seedDevice(deps, {
      deviceId: DEVICE_ID,
      pushToken: "existing-push-token",
      locationPushToken: "existing-location-token",
    });

    await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel", appVersion: "1.2.0" },
      },
      deps,
    );

    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.pushToken).toBe("existing-push-token");
    expect(stored?.locationPushToken).toBe("existing-location-token");
  });

  it("registers a device for a family-less caller under the implicit free plan (no Entitlements row, §4.1/002 §2.6)", async () => {
    const deps = buildDeps();

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: null,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
      },
      deps,
    );

    expect(result.created).toBe(true);
    expect(result.device).toMatchObject({ deviceId: DEVICE_ID, ownerUserId: "u1" });
    expect(result.features.subscriptionStatus).toBe("free");
    const stored = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(stored?.ownerUserId).toBe("u1");
  });

  it("stores a family-less caller's devices under their own uid partition (002 §2.4 — devices keyed by owner), isolated from other family-less callers reusing the same deviceId", async () => {
    const deps = buildDeps();

    await registerDevice(
      {
        uid: "u1",
        familyId: null,
        body: { deviceId: DEVICE_ID, platform: "android", model: "u1's phone", appVersion: "1.0.0" },
      },
      deps,
    );
    const result = await registerDevice(
      {
        uid: "u2",
        familyId: null,
        body: { deviceId: DEVICE_ID, platform: "ios", model: "u2's phone", appVersion: "1.0.0" },
      },
      deps,
    );

    // No deviceIdInUse conflict — each family-less caller has their own partition.
    expect(result.created).toBe(true);
    expect(result.device.ownerUserId).toBe("u2");
    const u1Device = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    const u2Device = await deps.deviceRepo.getDevice("u2", DEVICE_ID);
    expect(u1Device?.model).toBe("u1's phone");
    expect(u2Device?.model).toBe("u2's phone");
  });

  it("throws LIMIT_EXCEEDED for a family-less caller at the per-caller maxDevices cap", async () => {
    const deps = buildDeps();
    for (let i = 0; i < 10; i += 1) {
      deps.deviceRepo.seed("u1", {
        deviceId: `seed-device-${i}`,
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
    }

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: null,
          body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
        },
        deps,
      ),
      "LIMIT_EXCEEDED",
      { limit: "maxDevices" },
    );
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deviceRepo = new InMemoryDeviceRepo();
    const familyRepo = new InMemoryFamilyRepo();
    const entitlementsRepo = new InMemoryEntitlementsRepo(); // deliberately not seeded
    const clock = new FixedClock(new Date("2026-07-19T09:05:00Z"));

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
        },
        { deviceRepo, familyRepo, entitlementsRepo, clock },
      ),
      "INTERNAL_ERROR",
    );
  });

  it("throws VALIDATION_FAILED with details.fields: [\"platform\"] when platform is not android/ios", async () => {
    const deps = buildDeps();

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: { deviceId: DEVICE_ID, platform: "windows", model: "Pixel 8", appVersion: "1.0.0" },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["platform"] },
    );
  });

  it("throws VALIDATION_FAILED with details.fields: [\"deviceId\"] when deviceId is not a UUID", async () => {
    const deps = buildDeps();

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: { deviceId: "not-a-uuid", platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["deviceId"] },
    );
  });

  it("throws VALIDATION_FAILED for an empty deviceName", async () => {
    const deps = buildDeps();

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: {
            deviceId: DEVICE_ID,
            platform: "android",
            model: "Pixel 8",
            appVersion: "1.0.0",
            deviceName: "",
          },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["deviceName"] },
    );
  });

  it("throws VALIDATION_FAILED for a deviceName over 40 chars", async () => {
    const deps = buildDeps();

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: {
            deviceId: DEVICE_ID,
            platform: "android",
            model: "Pixel 8",
            appVersion: "1.0.0",
            deviceName: "x".repeat(41),
          },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["deviceName"] },
    );
  });

  it("throws VALIDATION_FAILED for an empty locationPushToken", async () => {
    const deps = buildDeps();

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: {
            deviceId: DEVICE_ID,
            platform: "android",
            model: "Pixel 8",
            appVersion: "1.0.0",
            locationPushToken: "",
          },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["locationPushToken"] },
    );
  });

  it("accepts registration without a pushToken (optional, §4.1)", async () => {
    const deps = buildDeps();

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
      },
      deps,
    );

    expect(result.created).toBe(true);
  });

  it('throws VALIDATION_FAILED with details.reason "deviceIdInUse" when the caller\'s own partition holds a mismatched-owner row (002 §2.4 data-integrity defense-in-depth)', async () => {
    // Post-re-key, Devices partitions are per-owner, so a genuine cross-user deviceId
    // collision can no longer surface via a point read in the caller's own partition (see
    // the isolation test below — that's now the expected, intentional behavior). This
    // check only guards the residual case where the caller's OWN partition somehow holds
    // an entity whose ownerUserId field disagrees with the partition (data corruption).
    const deps = buildDeps();
    deps.deviceRepo.seed("u1", {
      deviceId: DEVICE_ID,
      ownerUserId: "someone-else",
      platform: "android",
      model: "Someone's phone",
      appVersion: "1.0.0",
      deviceName: "Someone's phone",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { reason: "deviceIdInUse" },
    );
  });

  it('SECURITY: throws VALIDATION_FAILED "deviceIdInUse" when a family member deliberately re-registers a SIBLING\'s known deviceId under their own account (specs/001 §4.1 family-wide check)', async () => {
    // Exploit scenario: a non-parent member reads GET /v1/devices (§4.2, open-family
    // visibility — every member sees every other member's deviceId), learns a sibling's
    // deviceId, then tries to claim that exact id under their own uid. Pre-B8 this was
    // caught by the shared family partition; post-re-key it must be caught by an explicit
    // family-wide fan-out check, or a later by-deviceId lookup (a parent's PATCH
    // /devices/{deviceId}, a locate request's targetDeviceId) could silently resolve to
    // the attacker's device instead of the sibling's.
    const deps = buildDeps();
    await seedFamily(deps);
    // Noor (u2) already has DEVICE_ID registered.
    await registerDevice(
      {
        uid: "u2",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "ios", model: "Noor's phone", appVersion: "1.0.0" },
      },
      deps,
    );

    // Eric (u1), a family member with visibility into Noor's deviceId via GET /devices,
    // deliberately attempts to claim the exact same id.
    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: { deviceId: DEVICE_ID, platform: "android", model: "Attacker's phone", appVersion: "1.0.0" },
        },
        deps,
      ),
      "VALIDATION_FAILED",
      { reason: "deviceIdInUse" },
    );

    // And no attacker-owned row was ever written under that id.
    const u1Device = await deps.deviceRepo.getDevice("u1", DEVICE_ID);
    expect(u1Device).toBeNull();
  });

  it("allows a NEW member's first-ever deviceId to register normally when no other family member holds it (baseline, not a false positive)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);

    const result = await registerDevice(
      {
        uid: "u2",
        familyId: FAMILY_ID,
        body: { deviceId: OTHER_DEVICE_ID, platform: "ios", model: "Noor's phone", appVersion: "1.0.0" },
      },
      deps,
    );

    expect(result.created).toBe(true);
  });

  it("never runs the family-wide fan-out check on an upsert of the caller's own existing device (only a genuinely NEW registration needs the collision check)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Eric's phone", appVersion: "1.0.0" },
      },
      deps,
    );

    let listMembersCalls = 0;
    const originalListMembers = deps.familyRepo.listMembers.bind(deps.familyRepo);
    deps.familyRepo.listMembers = async (familyId: string) => {
      listMembersCalls++;
      return originalListMembers(familyId);
    };

    // Re-registering (upsert) the SAME deviceId as the SAME owner — this is the frequent,
    // routine path (every app launch/token-refresh/app-update, §4.1), so it must not pay
    // for a family-wide fan-out it doesn't need.
    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Eric's phone", appVersion: "1.0.1" },
      },
      deps,
    );

    expect(result.created).toBe(false);
    expect(listMembersCalls).toBe(0);
  });

  it("does not treat a stranger's device (not a member of this family) as a deviceIdInUse conflict — the fan-out only visits the family's roster partitions (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // Registered to someone entirely outside this family.
    deps.deviceRepo.seed("stranger", {
      deviceId: DEVICE_ID,
      ownerUserId: "stranger",
      platform: "ios",
      model: "Stranger's phone",
      appVersion: "1.0.0",
      deviceName: "Stranger's phone",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: DEVICE_ID, platform: "android", model: "Eric's phone", appVersion: "1.0.0" },
      },
      deps,
    );

    expect(result.created).toBe(true);
  });


  it("throws LIMIT_EXCEEDED with details.limit maxDevices at the plan cap", async () => {
    const deps = buildDeps();
    for (let i = 0; i < 10; i += 1) {
      seedDevice(deps, { deviceId: `seed-device-${i}` });
    }

    await expectAppError(
      registerDevice(
        {
          uid: "u1",
          familyId: FAMILY_ID,
          body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.0.0" },
        },
        deps,
      ),
      "LIMIT_EXCEEDED",
      { limit: "maxDevices" },
    );
  });

  it("never counts an upsert of an existing device against the cap", async () => {
    const deps = buildDeps();
    for (let i = 0; i < 9; i += 1) {
      seedDevice(deps, { deviceId: `seed-device-${i}` });
    }
    // 10th device already registered to this same user — an upsert, not a new registration.
    seedDevice(deps, { deviceId: OTHER_DEVICE_ID });

    const result = await registerDevice(
      {
        uid: "u1",
        familyId: FAMILY_ID,
        body: { deviceId: OTHER_DEVICE_ID, platform: "ios", model: "iPhone", appVersion: "2.0.0" },
      },
      deps,
    );

    expect(result.created).toBe(false);
  });

  // specs/001 §4.1, 011 §4 — staleNudgeEnabled.
  it("first registration stores staleNudgeEnabled true and returns it in the §4.1 response object", async () => {
    const deps = buildDeps();

    const result = await registerDevice({ uid: "u1", familyId: FAMILY_ID, body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.1.0" } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(true);
    expect((await deps.deviceRepo.getDevice("u1", DEVICE_ID))?.staleNudgeEnabled).toBe(true);
  });

  it("re-registration preserves staleNudgeEnabled false (an upsert never resets the owner's opt-out)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { deviceId: DEVICE_ID, staleNudgeEnabled: false });

    const result = await registerDevice({ uid: "u1", familyId: FAMILY_ID, body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.1.0" } }, deps);

    expect(result.created).toBe(false);
    expect(result.device.staleNudgeEnabled).toBe(false);
    expect((await deps.deviceRepo.getDevice("u1", DEVICE_ID))?.staleNudgeEnabled).toBe(false);
  });

  it("a legacy row without the property reads as staleNudgeEnabled true on re-registration", async () => {
    const deps = buildDeps();
    seedDevice(deps, { deviceId: DEVICE_ID });

    const result = await registerDevice({ uid: "u1", familyId: FAMILY_ID, body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.1.0" } }, deps);

    expect(result.device.staleNudgeEnabled).toBe(true);
  });

  it("re-registration preserves lastNudgedAt (written only by the nudger) and never exposes it", async () => {
    const deps = buildDeps();
    seedDevice(deps, { deviceId: DEVICE_ID, lastNudgedAt: "2026-07-18T10:00:00Z" });

    const result = await registerDevice({ uid: "u1", familyId: FAMILY_ID, body: { deviceId: DEVICE_ID, platform: "android", model: "Pixel 8", appVersion: "1.1.0" } }, deps);

    expect((await deps.deviceRepo.getDevice("u1", DEVICE_ID))?.lastNudgedAt).toBe("2026-07-18T10:00:00Z");
    expect(result.device).not.toHaveProperty("lastNudgedAt");
  });
});
