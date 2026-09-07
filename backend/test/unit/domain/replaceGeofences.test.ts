import { describe, expect, it } from "vitest";
import { replaceGeofences } from "../../../src/domain/geofence/replaceGeofences";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryGeofenceConfigRepo } from "../../fakes/inMemoryGeofenceConfigRepo";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FakePushSender } from "../../fakes/fakePushSender";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  return {
    geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    entitlementsRepo,
    pushSender: new FakePushSender(),
  };
}

// specs/002 §2.4 (B8 re-key) — the push fan-out now requires a family roster to find each
// member's Devices partition.
async function seedFamily(deps: ReturnType<typeof buildDeps>): Promise<void> {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: "u1",
    createdAt: "2026-07-01T00:00:00Z",
  });
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
}

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b",
    ownerUserId: "u1",
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Pixel 8",
    pushToken: "fcm-token-a",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    ...overrides,
  };
}

function geofence(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    geofenceId: "gf_home",
    name: "Home",
    lat: 51.0543,
    lon: 3.7174,
    radiusM: 150,
    icon: "home",
    notifyOnEnter: true,
    notifyOnExit: true,
    ...overrides,
  };
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    familyId: FAMILY_ID as string | null,
    role: "parent" as "parent" | "member" | null,
    ifMatch: "0" as string | null,
    body: { geofences: [geofence()] },
    ...overrides,
  };
}

describe("domain/geofence/replaceGeofences", () => {
  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();
    await expectAppError(replaceGeofences(baseInput({ familyId: null }), deps), "FAMILY_NOT_FOUND");
  });

  it("throws AUTH_FORBIDDEN when the caller is not a parent", async () => {
    const deps = buildDeps();
    await expectAppError(replaceGeofences(baseInput({ role: "member" }), deps), "AUTH_FORBIDDEN");
  });

  it("throws VALIDATION_FAILED with details.fields: [\"If-Match\"] when If-Match is missing", async () => {
    const deps = buildDeps();
    await expectAppError(replaceGeofences(baseInput({ ifMatch: null }), deps), "VALIDATION_FAILED", {
      fields: ["If-Match"],
    });
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = {
      geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
      deviceRepo: new InMemoryDeviceRepo(),
      familyRepo: new InMemoryFamilyRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
      pushSender: new FakePushSender(),
    };
    await expectAppError(replaceGeofences(baseInput(), deps), "INTERNAL_ERROR");
  });

  it("\"0\" sentinel creates the first config: version 1, a fresh (non-\"0\") etag", async () => {
    const deps = buildDeps();

    const result = await replaceGeofences(baseInput(), deps);

    expect(result.version).toBe(1);
    expect(result.etag).not.toBe("0");
    expect(result.geofences).toEqual([geofence()]);
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("\"0\" sentinel conflicts (409) when a config already exists", async () => {
    const deps = buildDeps();
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [] }, '"existing-etag"');

    await expectAppError(replaceGeofences(baseInput({ ifMatch: "0" }), deps), "GEOFENCE_VERSION_CONFLICT", {
      currentEtag: '"existing-etag"',
    });
  });

  it("a matching If-Match updates the config: version increments, a new etag is returned", async () => {
    const deps = buildDeps();
    deps.geofenceConfigRepo.seedConfig(
      FAMILY_ID,
      { version: 4, geofences: [geofence() as never] },
      '"0x8DC5F3A9B2C1D40"',
    );

    const result = await replaceGeofences(
      baseInput({ ifMatch: '"0x8DC5F3A9B2C1D40"', body: { geofences: [geofence({ name: "Home 2" })] } }),
      deps,
    );

    expect(result.version).toBe(5);
    expect(result.etag).not.toBe('"0x8DC5F3A9B2C1D40"');
    expect(result.geofences[0]?.name).toBe("Home 2");
  });

  it("a stale If-Match returns 409 GEOFENCE_VERSION_CONFLICT with details.currentEtag", async () => {
    const deps = buildDeps();
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 4, geofences: [] }, '"current-etag"');

    await expectAppError(
      replaceGeofences(baseInput({ ifMatch: '"stale-etag"' }), deps),
      "GEOFENCE_VERSION_CONFLICT",
      { currentEtag: '"current-etag"' },
    );
  });

  it("throws LIMIT_EXCEEDED with details.limit: \"maxGeofences\" beyond the plan cap (free = 20)", async () => {
    const deps = buildDeps();
    const geofences = Array.from({ length: 21 }, (_, i) => geofence({ geofenceId: `gf_g${i}` }));

    await expectAppError(replaceGeofences(baseInput({ body: { geofences } }), deps), "LIMIT_EXCEEDED", {
      limit: "maxGeofences",
    });
  });

  it("accepts exactly maxGeofences entries (boundary: only STRICTLY more than the cap fails)", async () => {
    const deps = buildDeps();
    const geofences = Array.from({ length: 20 }, (_, i) => geofence({ geofenceId: `gf_g${i}` }));

    const result = await replaceGeofences(baseInput({ body: { geofences } }), deps);

    expect(result.geofences).toHaveLength(20);
  });

  it("throws VALIDATION_FAILED with details.fields for radiusM below 100", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ radiusM: 99 })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].radiusM"] },
    );
  });

  it("throws VALIDATION_FAILED with details.fields for radiusM above 5000", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ radiusM: 5001 })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].radiusM"] },
    );
  });

  it("accepts radiusM at the 100 and 5000 boundaries", async () => {
    const deps = buildDeps();
    const result = await replaceGeofences(
      baseInput({
        body: {
          geofences: [
            geofence({ geofenceId: "gf_a", radiusM: 100 }),
            geofence({ geofenceId: "gf_b", radiusM: 5000 }),
          ],
        },
      }),
      deps,
    );
    expect(result.geofences).toHaveLength(2);
  });

  it("throws VALIDATION_FAILED for an empty name", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ name: "" })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].name"] },
    );
  });

  it("throws VALIDATION_FAILED for a name over 40 chars (001 §1.4/B29 — narrowed from the §7.2 prose's stale 50)", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ name: "x".repeat(41) })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].name"] },
    );
  });

  it("accepts a name at the 40-char boundary", async () => {
    const deps = buildDeps();
    const result = await replaceGeofences(
      baseInput({ body: { geofences: [geofence({ name: "x".repeat(40) })] } }),
      deps,
    );
    expect(result.geofences[0]?.name).toBe("x".repeat(40));
  });

  it("normalizes name at write time before storing (strips a right-to-left override, 001 §1.4/B29)", async () => {
    const deps = buildDeps();
    const result = await replaceGeofences(
      baseInput({ body: { geofences: [geofence({ name: "Home‮emoH" })] } }),
      deps,
    );
    expect(result.geofences[0]?.name).toBe("HomeemoH");
  });

  it("throws VALIDATION_FAILED (not an empty stored name) when name is only control characters", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ name: "‮‮" })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].name"] },
    );
  });

  it("throws VALIDATION_FAILED for an icon over 30 chars", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ icon: "x".repeat(31) })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].icon"] },
    );
  });

  it("throws VALIDATION_FAILED for a geofenceId not matching gf_[a-z0-9-]{1,30}", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ geofenceId: "home" })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].geofenceId"] },
    );
  });

  it("throws VALIDATION_FAILED for a geofenceId with a prefix before gf_ (anchored at the start)", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ geofenceId: "xgf_home" })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].geofenceId"] },
    );
  });

  it("throws VALIDATION_FAILED for a geofenceId with a disallowed trailing character (anchored at the end)", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(baseInput({ body: { geofences: [geofence({ geofenceId: "gf_home!" })] } }), deps),
      "VALIDATION_FAILED",
      { fields: ["geofences[0].geofenceId"] },
    );
  });

  it("throws VALIDATION_FAILED with bracket-notation fields for duplicate geofenceId slugs", async () => {
    const deps = buildDeps();
    await expectAppError(
      replaceGeofences(
        baseInput({
          body: {
            geofences: [geofence({ geofenceId: "gf_home" }), geofence({ geofenceId: "gf_home", name: "Home 2" })],
          },
        }),
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["geofences[1].geofenceId"] },
    );
  });

  it("accepts an empty geofences array (clearing the config)", async () => {
    const deps = buildDeps();
    const result = await replaceGeofences(baseInput({ body: { geofences: [] } }), deps);
    expect(result.geofences).toEqual([]);
    expect(result.version).toBe(1);
  });

  it("sends GEOFENCE_CONFIG_CHANGED to ALL family devices (not excluding anyone) with the new etag, fanning out per-member (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u1", device({ deviceId: "device-a", ownerUserId: "u1" }));
    deps.deviceRepo.seed("u2", device({ deviceId: "device-b", ownerUserId: "u2", pushToken: "fcm-token-b" }));

    const result = await replaceGeofences(baseInput(), deps);

    expect(deps.pushSender.sent).toHaveLength(2);
    expect(deps.pushSender.sent.map((m) => m.token).sort()).toEqual(["fcm-token-a", "fcm-token-b"]);
    for (const message of deps.pushSender.sent) {
      expect(message.type).toBe("GEOFENCE_CONFIG_CHANGED");
      expect(message.data).toEqual({ type: "GEOFENCE_CONFIG_CHANGED", etag: result.etag });
    }

    // A successful ("ok") send must NOT mark the device pushInvalid.
    expect((await deps.deviceRepo.getDevice("u1", "device-a"))?.pushInvalid).toBe(false);
    expect((await deps.deviceRepo.getDevice("u2", "device-b"))?.pushInvalid).toBe(false);
  });

  it("never fans out to a stranger's device (not a member of this family) — fan-out only visits the family's roster partitions (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("stranger", device({ deviceId: "device-stranger", ownerUserId: "stranger" }));

    await replaceGeofences(baseInput(), deps);

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("skips push fan-out for devices with no pushToken or pushInvalid: true", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u1", device({ deviceId: "device-a", pushToken: undefined }));
    deps.deviceRepo.seed("u2", device({ deviceId: "device-b", ownerUserId: "u2", pushInvalid: true }));

    await replaceGeofences(baseInput(), deps);

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("marks a device pushInvalid: true when FCM reports an invalid token", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u1", device({ deviceId: "device-a" }));
    deps.pushSender.setOutcome("invalidToken");

    await replaceGeofences(baseInput(), deps);

    const stored = await deps.deviceRepo.getDevice("u1", "device-a");
    expect(stored?.pushInvalid).toBe(true);
  });

  it("does not fail the request when a push send throws (best-effort fan-out)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed("u1", device({ deviceId: "device-a" }));
    deps.pushSender.send = async () => {
      throw new Error("transport failure");
    };

    const result = await replaceGeofences(baseInput(), deps);

    expect(result.version).toBe(1);
  });
});
