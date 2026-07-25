import { describe, expect, it } from "vitest";
import { reportLocations } from "../../../src/domain/location/reportLocations";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";
import { InMemoryIdempotencyRepo } from "../../fakes/inMemoryIdempotencyRepo";
import { InMemoryHistoryStore } from "../../fakes/inMemoryHistoryStore";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryGeofenceConfigRepo } from "../../fakes/inMemoryGeofenceConfigRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupLastKnownRepo } from "../../fakes/inMemoryGroupLastKnownRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord, GroupMeta } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const OTHER_DEVICE_ID = "4f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2c";
const USER_ID = "u1";
const NOW = "2026-07-19T09:10:00Z";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  const familyRepo = new InMemoryFamilyRepo();
  // Write-time family-existence guard (002 §4.2, B19 review-gate fix): seeded here so every
  // existing "has a family" test keeps seeing FAMILY_ID as alive at write time — the guard
  // itself is exercised by the dedicated describe block below, which deletes it mid-request.
  familyRepo.seed({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: USER_ID,
    createdAt: "2026-07-01T00:00:00Z",
  });
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    lastKnownRepo: new InMemoryLastKnownRepo(),
    idempotencyRepo: new InMemoryIdempotencyRepo(),
    historyStore: new InMemoryHistoryStore(),
    usageRepo: new InMemoryUsageRepo(),
    geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
    entitlementsRepo,
    userRepo: new InMemoryUserRepo(),
    familyRepo,
    groupRepo: new InMemoryGroupRepo(),
    groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
    clock: new FixedClock(new Date(NOW)),
  };
}

// specs/002 §2.10 — seeds a group's meta + the reporter's membership (both the Groups
// roster row and the Users `group:` reverse-index row the fan-out reads).
async function seedActiveGroupMembership(
  deps: ReturnType<typeof buildDeps>,
  groupId: string,
  overrides: Partial<GroupMeta> = {},
): Promise<void> {
  const meta: GroupMeta = {
    groupId,
    name: "Festival crew",
    ownerUserId: USER_ID,
    createdAt: "2026-07-01T00:00:00Z",
    endsAt: "2026-08-02T22:00:00Z",
    expiryPolicy: "delete",
    code: "ABCD1234",
    ...overrides,
  };
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(groupId, {
    userId: USER_ID,
    role: "owner",
    displayName: "Eric",
    joinedAt: meta.createdAt,
  });
  await deps.userRepo.addGroupMembership(USER_ID, { groupId, role: "owner", joinedAt: meta.createdAt });
}

// specs/002 §2.4 (B8 re-key) — Devices are keyed by ownerUserId, never familyId. Seeds
// under the record's own ownerUserId partition (defaulting to USER_ID).
function seedDevice(deps: ReturnType<typeof buildDeps>, overrides: Partial<DeviceRecord> = {}): void {
  const device: DeviceRecord = {
    deviceId: DEVICE_ID,
    ownerUserId: USER_ID,
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Pixel 8",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  };
  deps.deviceRepo.seed(device.ownerUserId, device);
}

function fix(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    fixId: "a1e2b3c4-0000-4000-8000-000000000001",
    recordedAt: "2026-07-19T09:00:00Z",
    lat: 51.0543,
    lon: 3.7174,
    accuracyM: 12.5,
    batteryPct: 78,
    source: "periodic",
    ...overrides,
  };
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    uid: USER_ID,
    familyId: FAMILY_ID as string | null,
    deviceId: DEVICE_ID as string | null,
    body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes: [fix()] },
    ...overrides,
  };
}

describe("domain/location/reportLocations", () => {
  it("accepts a valid batch: accepted count, duplicates 0, lastKnownUpdated true, piggyback fields", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    const result = await reportLocations(
      {
        uid: USER_ID,
        familyId: FAMILY_ID,
        deviceId: DEVICE_ID,
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001", recordedAt: "2026-07-19T09:00:00Z" }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:05:00Z" }),
          ],
        },
      },
      deps,
    );

    expect(result.accepted).toBe(2);
    expect(result.duplicates).toBe(0);
    expect(result.lastKnownUpdated).toBe(true);
    expect(result.deviceSettings).toEqual({ syncIntervalMinutes: 15, trackingEnabled: true });
    expect(result.geofenceEtag).toBe("0");
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deviceRepo = new InMemoryDeviceRepo();
    deviceRepo.seed(USER_ID, {
      deviceId: DEVICE_ID,
      ownerUserId: USER_ID,
      platform: "android",
      model: "Pixel 8",
      appVersion: "1.0.0",
      deviceName: "Pixel 8",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });
    const deps = {
      deviceRepo,
      lastKnownRepo: new InMemoryLastKnownRepo(),
      idempotencyRepo: new InMemoryIdempotencyRepo(),
      historyStore: new InMemoryHistoryStore(),
      usageRepo: new InMemoryUsageRepo(),
      geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
      userRepo: new InMemoryUserRepo(),
      familyRepo: new InMemoryFamilyRepo(),
      groupRepo: new InMemoryGroupRepo(),
      groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
      clock: new FixedClock(new Date(NOW)),
    };

    await expectAppError(reportLocations(baseInput(), deps), "INTERNAL_ERROR");
  });

  it("batch idempotency: replaying the same batchId returns accepted 0, duplicates n, and performs no further writes", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    const body = {
      batchId: "b7f2c1d0-0000-4000-8000-000000000001",
      fixes: [fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" })],
    };

    const first = await reportLocations({ uid: USER_ID, familyId: FAMILY_ID, deviceId: DEVICE_ID, body }, deps);
    expect(first.accepted).toBe(1);

    const replay = await reportLocations({ uid: USER_ID, familyId: FAMILY_ID, deviceId: DEVICE_ID, body }, deps);

    expect(replay.accepted).toBe(0);
    expect(replay.duplicates).toBe(1);
    expect(replay.lastKnownUpdated).toBe(false);
    expect(replay.deviceSettings).toEqual({ syncIntervalMinutes: 15, trackingEnabled: true });
    expect(replay.geofenceEtag).toBe("0");
    expect(replay.features).toEqual(getFeatures("free"));

    expect(deps.historyStore.fixes.length).toBe(1); // no second append
    expect(await deps.usageRepo.get(FAMILY_ID, "locationBatches", "2026-07-19")).toBe(1);
    expect(await deps.usageRepo.get(FAMILY_ID, "fixes", "2026-07-19")).toBe(1);
  });

  it("stores the batch's actual receivedAt and fixCount in the idempotency marker meta", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    const body = {
      batchId: "b7f2c1d0-0000-4000-8000-000000000001",
      fixes: [
        fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" }),
        fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:01:00Z" }),
      ],
    };

    await reportLocations({ uid: USER_ID, familyId: FAMILY_ID, deviceId: DEVICE_ID, body }, deps);

    expect(deps.idempotencyRepo.getBatchMarkerMeta(DEVICE_ID, body.batchId)).toEqual({
      receivedAt: new Date(NOW).toISOString(),
      fixCount: 2,
    });
  });

  it("writes no idempotency marker for a rejected (validation-failed) batch", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    const batchId = "b7f2c1d0-0000-4000-8000-000000000099";

    await expectAppError(
      reportLocations(
        { uid: USER_ID, familyId: FAMILY_ID, deviceId: DEVICE_ID, body: { batchId, fixes: [] } },
        deps,
      ),
      "VALIDATION_FAILED",
    );

    // No marker was written by the failed attempt -> a fresh insert for the same id still succeeds.
    const inserted = await deps.idempotencyRepo.tryInsertBatchMarker(DEVICE_ID, batchId, {
      receivedAt: NOW,
      fixCount: 0,
    });
    expect(inserted).toBe(true);
  });

  it("throws VALIDATION_FAILED for an empty batch", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expectAppError(
      reportLocations(baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes: [] } }), deps),
      "VALIDATION_FAILED",
    );
  });

  it("throws LOCATION_BATCH_TOO_LARGE with details.max: 100 for a batch of 101 fixes", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    const fixes = Array.from({ length: 101 }, (_, i) =>
      fix({ fixId: `a1e2b3c4-0000-4000-8000-${String(i).padStart(12, "0")}` }),
    );

    await expectAppError(
      reportLocations(
        baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes } }),
        deps,
      ),
      "LOCATION_BATCH_TOO_LARGE",
      { max: 100 },
    );
  });

  it("accepts a batch of exactly 100 fixes (the boundary is > 100, not >= 100)", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    const fixes = Array.from({ length: 100 }, (_, i) =>
      fix({ fixId: `a1e2b3c4-0000-4000-8000-${String(i).padStart(12, "0")}` }),
    );

    const result = await reportLocations(
      baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes } }),
      deps,
    );

    expect(result.accepted).toBe(100);
  });

  it("throws VALIDATION_FAILED (not a crash) when the body is null", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expectAppError(reportLocations(baseInput({ body: null }), deps), "VALIDATION_FAILED");
  });

  it("throws VALIDATION_FAILED (not a crash) when the body is undefined", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expectAppError(reportLocations(baseInput({ body: undefined }), deps), "VALIDATION_FAILED");
  });

  it("throws VALIDATION_FAILED (not LOCATION_BATCH_TOO_LARGE) when fixes is not an array", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    // A string has a `.length` property but is not an array — must not satisfy the size check.
    const longString = "x".repeat(101);

    await expectAppError(
      reportLocations(
        baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes: longString } }),
        deps,
      ),
      "VALIDATION_FAILED",
    );
  });

  it("throws VALIDATION_FAILED with details.fields listing the offending recordedAt for clock skew (>5 min future)", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    // NOW = 2026-07-19T09:10:00Z; +5min = 09:15:00Z. 09:16:00Z is 1 min past the limit.
    const fixes = [
      fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001", recordedAt: "2026-07-19T09:00:00Z" }),
      fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:16:00Z" }),
    ];

    await expectAppError(
      reportLocations(baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes } }), deps),
      "VALIDATION_FAILED",
      { fields: ["fixes[1].recordedAt"] },
    );
  });

  it("accepts a fix recordedAt exactly 5 minutes in the future (boundary: only STRICTLY more than 5 min fails)", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    // NOW = 09:10:00Z; +5min exactly = 09:15:00Z.
    const result = await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [fix({ recordedAt: "2026-07-19T09:15:00Z" })],
        },
      }),
      deps,
    );

    expect(result.accepted).toBe(1);
  });

  it("accepts a fix recordedAt a couple minutes in the future (within the 5-minute tolerance)", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    // NOW = 09:10:00Z; +2min = 09:12:00Z, comfortably inside the 5-minute tolerance.
    const result = await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [fix({ recordedAt: "2026-07-19T09:12:00Z" })],
        },
      }),
      deps,
    );

    expect(result.accepted).toBe(1);
  });

  it("throws DEVICE_NOT_FOUND when X-Device-Id header is missing", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expect(reportLocations(baseInput({ deviceId: null }), deps)).rejects.toMatchObject({
      code: "DEVICE_NOT_FOUND",
      message: "X-Device-Id header is required",
    });
  });

  it("throws DEVICE_NOT_FOUND when the device does not exist", async () => {
    const deps = buildDeps();
    // no device seeded at all

    await expectAppError(reportLocations(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("throws DEVICE_NOT_FOUND when the device is registered to a different user (own-partition lookup finds nothing, 002 §2.4)", async () => {
    const deps = buildDeps();
    seedDevice(deps, { ownerUserId: "someone-else" });

    await expectAppError(reportLocations(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("throws DEVICE_NOT_FOUND when the caller's own partition holds a mismatched-owner row (data-integrity defense-in-depth)", async () => {
    const deps = buildDeps();
    // Deliberately seeded under the CALLER's own partition (USER_ID) but with a different
    // ownerUserId field — structurally shouldn't happen (every write keys by its own
    // ownerUserId), kept as a belt-and-suspenders check.
    deps.deviceRepo.seed(USER_ID, {
      deviceId: DEVICE_ID,
      ownerUserId: "someone-else",
      platform: "android",
      model: "Pixel 8",
      appVersion: "1.0.0",
      deviceName: "Pixel 8",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });

    await expectAppError(reportLocations(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("throws TRACKING_PAUSED with error.details.deviceSettings when the device is paused", async () => {
    const deps = buildDeps();
    seedDevice(deps, { trackingEnabled: false, syncIntervalMinutes: 30 });

    await expectAppError(reportLocations(baseInput(), deps), "TRACKING_PAUSED", {
      deviceSettings: { syncIntervalMinutes: 30, trackingEnabled: false },
    });
  });

  it("last-known: does not update when the batch's newest fix is not newer than the stored one", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    deps.lastKnownRepo.seed(USER_ID, {
      deviceId: DEVICE_ID,
      lat: 51.0,
      lon: 3.7,
      accuracyM: 10,
      batteryPct: 90,
      recordedAt: "2026-07-19T09:05:00Z",
      receivedAt: "2026-07-19T09:05:02Z",
      source: "periodic",
    });

    const result = await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [fix({ recordedAt: "2026-07-19T09:00:00Z" })], // older than stored 09:05:00Z
        },
      }),
      deps,
    );

    expect(result.lastKnownUpdated).toBe(false);
    const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
    expect(stored?.lat).toBe(51.0); // unchanged
  });

  it("last-known: picks the batch's newest fix by recordedAt, not the last array element", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({
              fixId: "a1e2b3c4-0000-4000-8000-000000000001",
              recordedAt: "2026-07-19T09:05:00Z", // newest, but listed FIRST
              lat: 52.0,
            }),
            fix({
              fixId: "a1e2b3c4-0000-4000-8000-000000000002",
              recordedAt: "2026-07-19T09:00:00Z", // older, listed last
              lat: 51.0,
            }),
          ],
        },
      }),
      deps,
    );

    const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
    expect(stored?.lat).toBe(52.0);
    expect(stored?.recordedAt).toBe("2026-07-19T09:05:00Z");
  });

  it("last-known: replaces the running newest mid-batch when a later array element is actually newer", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001", recordedAt: "2026-07-19T09:00:00Z", lat: 10 }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:05:00Z", lat: 20 }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000003", recordedAt: "2026-07-19T09:02:00Z", lat: 30 }),
          ],
        },
      }),
      deps,
    );

    const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
    expect(stored?.lat).toBe(20); // the middle fix (09:05) is the newest of the three
  });

  it("last-known: on a recordedAt tie, the earlier array element wins (strict > , not >=)", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001", recordedAt: "2026-07-19T09:00:00Z", lat: 10 }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:00:00Z", lat: 20 }),
          ],
        },
      }),
      deps,
    );

    const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
    expect(stored?.lat).toBe(10); // first element kept; a `>=` bug would let the second replace it
  });

  it("last-known: carries altitudeM/speedMps/bearingDeg from the newest fix when present", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [fix({ altitudeM: 8.0, speedMps: 1.5, bearingDeg: 90 })],
        },
      }),
      deps,
    );

    const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
    expect(stored?.altitudeM).toBe(8.0);
    expect(stored?.speedMps).toBe(1.5);
    expect(stored?.bearingDeg).toBe(90);
  });

  it("last-known: omits altitudeM/speedMps/bearingDeg when absent from the newest fix (not null)", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(baseInput(), deps);

    const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
    expect("altitudeM" in (stored as object)).toBe(false);
    expect("speedMps" in (stored as object)).toBe(false);
    expect("bearingDeg" in (stored as object)).toBe(false);
  });

  it("accepts every valid fix source: periodic, locate, geofence, manual", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    const result = await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001", source: "periodic" }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", source: "locate" }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000003", source: "geofence" }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000004", source: "manual" }),
          ],
        },
      }),
      deps,
    );

    expect(result.accepted).toBe(4);
  });

  it("appends one history fix per accepted fix, omitting unset optional fields (not null)", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" }), // no optionals
            fix({
              fixId: "a1e2b3c4-0000-4000-8000-000000000002",
              recordedAt: "2026-07-19T09:01:00Z",
              altitudeM: 8.0,
              speedMps: 1.5,
              bearingDeg: 90,
            }),
          ],
        },
      }),
      deps,
    );

    expect(deps.historyStore.fixes.length).toBe(2);
    const [withoutOptionals, withOptionals] = deps.historyStore.fixes;
    expect(withoutOptionals!.familyId).toBe(FAMILY_ID);
    expect(withoutOptionals!.userId).toBe(USER_ID);
    expect(withoutOptionals!.deviceId).toBe(DEVICE_ID);
    expect("altitudeM" in withoutOptionals!.fix).toBe(false);
    expect("speedMps" in withoutOptionals!.fix).toBe(false);
    expect("bearingDeg" in withoutOptionals!.fix).toBe(false);
    expect(withoutOptionals!.fix.receivedAt).toBe(new Date(NOW).toISOString());

    expect(withOptionals!.fix.altitudeM).toBe(8.0);
    expect(withOptionals!.fix.speedMps).toBe(1.5);
    expect(withOptionals!.fix.bearingDeg).toBe(90);
  });

  it("increments locationBatches and fixes usage on an accepted batch", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await reportLocations(
      baseInput({
        body: {
          batchId: "b7f2c1d0-0000-4000-8000-000000000001",
          fixes: [
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:01:00Z" }),
            fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000003", recordedAt: "2026-07-19T09:02:00Z" }),
          ],
        },
      }),
      deps,
    );

    expect(await deps.usageRepo.get(FAMILY_ID, "locationBatches", "2026-07-19")).toBe(1);
    expect(await deps.usageRepo.get(FAMILY_ID, "fixes", "2026-07-19")).toBe(3);
  });

  it("never increments usage for a rejected (validation-failed) batch", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expectAppError(
      reportLocations(baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes: [] } }), deps),
      "VALIDATION_FAILED",
    );

    expect(await deps.usageRepo.get(FAMILY_ID, "locationBatches", "2026-07-19")).toBe(0);
    expect(await deps.usageRepo.get(FAMILY_ID, "fixes", "2026-07-19")).toBe(0);
  });

  it("reflects the family's current geofenceEtag (piggyback, §5.1)", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    deps.geofenceConfigRepo.seed(FAMILY_ID, '"0x8DC5F3A9B2C1D40"');

    const result = await reportLocations(baseInput(), deps);

    expect(result.geofenceEtag).toBe('"0x8DC5F3A9B2C1D40"');
  });

  it("throws VALIDATION_FAILED with details.fields: [\"lat\"] for an out-of-range latitude", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expectAppError(
      reportLocations(
        baseInput({
          body: {
            batchId: "b7f2c1d0-0000-4000-8000-000000000001",
            fixes: [fix({ lat: 95 })],
          },
        }),
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["fixes[0].lat"] },
    );
  });

  it("throws VALIDATION_FAILED with details.fields: [\"source\"] for an invalid source", async () => {
    const deps = buildDeps();
    seedDevice(deps);

    await expectAppError(
      reportLocations(
        baseInput({
          body: {
            batchId: "b7f2c1d0-0000-4000-8000-000000000001",
            fixes: [fix({ source: "bogus" })],
          },
        }),
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["fixes[0].source"] },
    );
  });

  it("uses bracket-notation array indices for a deep validation error (kills the validate.ts path-join mutant)", async () => {
    const deps = buildDeps();
    seedDevice(deps);
    const fixes = [
      fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" }),
      fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:01:00Z" }),
      fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000003", recordedAt: "2026-07-19T09:02:00Z" }),
      fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000004", recordedAt: "not-a-valid-datetime" }),
    ];

    await expectAppError(
      reportLocations(
        baseInput({ body: { batchId: "b7f2c1d0-0000-4000-8000-000000000001", fixes } }),
        deps,
      ),
      "VALIDATION_FAILED",
      { fields: ["fixes[3].recordedAt"] },
    );
  });

  // specs/001 §1.5 step 4 / §5.1 — location reporting works WITHOUT a family (unlike §5.2/
  // §6/§7), but history append is gated on having one (005 §3): a family-less user's fixes
  // update last-known only, never durable history.
  describe("family-less caller (001 §1.5 step 4, §5.1)", () => {
    function familyLessInput(overrides: Record<string, unknown> = {}) {
      return baseInput({ familyId: null, ...overrides });
    }

    it("accepts a batch: last-known updates, features implicit free, geofenceEtag '0' (no family config to sync)", async () => {
      const deps = buildDeps();
      seedDevice(deps);

      const result = await reportLocations(familyLessInput(), deps);

      expect(result.accepted).toBe(1);
      expect(result.lastKnownUpdated).toBe(true);
      expect(result.geofenceEtag).toBe("0");
      expect(result.features).toEqual(getFeatures("free"));
      const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
      expect(stored?.lat).toBe(51.0543);
    });

    it("history gate: never appends to history for a family-less caller, even though last-known updates (005 §3)", async () => {
      const deps = buildDeps();
      seedDevice(deps);

      await reportLocations(
        familyLessInput({
          body: {
            batchId: "b7f2c1d0-0000-4000-8000-000000000001",
            fixes: [
              fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" }),
              fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:01:00Z" }),
            ],
          },
        }),
        deps,
      );

      expect(deps.historyStore.fixes).toEqual([]);
    });

    it("records usage under the caller's own uid, not a familyId (002 §2.9)", async () => {
      const deps = buildDeps();
      seedDevice(deps);

      await reportLocations(familyLessInput(), deps);

      expect(await deps.usageRepo.get(USER_ID, "locationBatches", "2026-07-19")).toBe(1);
      expect(await deps.usageRepo.get(USER_ID, "fixes", "2026-07-19")).toBe(1);
    });

    it("still enforces TRACKING_PAUSED for a paused family-less device", async () => {
      const deps = buildDeps();
      seedDevice(deps, { trackingEnabled: false });

      await expectAppError(reportLocations(familyLessInput(), deps), "TRACKING_PAUSED");
    });

    it("still enforces the §1.2 X-Device-Id ownership check for a family-less caller", async () => {
      const deps = buildDeps();
      seedDevice(deps, { ownerUserId: "someone-else" });

      await expectAppError(reportLocations(familyLessInput(), deps), "DEVICE_NOT_FOUND");
    });

    it("batch idempotency still applies without a family", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      const body = {
        batchId: "b7f2c1d0-0000-4000-8000-000000000001",
        fixes: [fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" })],
      };

      const first = await reportLocations(familyLessInput({ body }), deps);
      expect(first.accepted).toBe(1);

      const replay = await reportLocations(familyLessInput({ body }), deps);
      expect(replay.accepted).toBe(0);
      expect(replay.duplicates).toBe(1);
    });
  });

  // Review-gate fix (security, Major): the auth-context familyId snapshot (input.familyId)
  // is taken BEFORE this function runs; if a concurrent DELETE /families/me (001 §13.3)
  // completes while this batch is in flight, the family-scoped writes below must not
  // silently resurrect data under the erased family (002 §4.2's normative write-time
  // guard, 008 §5.2/§9).
  describe("write-time family-existence guard (002 §4.2, in-flight erasure race)", () => {
    const GUARD_GROUP_ID = "grp_9J2Kq7Lm3NpR5sTvWxYz";

    // Simulates a family deletion completing in the exact window between the request's
    // auth-context snapshot and the guard's own read: wraps the fake's getFamilyMeta so
    // that, at the moment the ingest path performs its write-time re-check, the deletion
    // has ALREADY landed (mirrors the groupSweeper TOCTOU test idiom in this codebase).
    function raceFamilyDeletionIntoGuardRead(deps: ReturnType<typeof buildDeps>): void {
      const realGetFamilyMeta = deps.familyRepo.getFamilyMeta.bind(deps.familyRepo);
      deps.familyRepo.getFamilyMeta = async (familyId: string) => {
        await deps.familyRepo.deleteFamilyMeta(familyId);
        return realGetFamilyMeta(familyId);
      };
    }

    it("skips the history append and the family-keyed usage row when the family is gone by write time, but the batch still succeeds with last-known and group fan-out intact (008 §9)", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GUARD_GROUP_ID);
      raceFamilyDeletionIntoGuardRead(deps);

      const result = await reportLocations(baseInput(), deps); // input.familyId is still the stale FAMILY_ID snapshot

      expect(result.accepted).toBe(1);
      expect(result.duplicates).toBe(0);

      // (a) no history line, no family-keyed usage row.
      expect(deps.historyStore.fixes).toEqual([]);
      expect(await deps.usageRepo.get(FAMILY_ID, "locationBatches", "2026-07-19")).toBe(0);
      expect(await deps.usageRepo.get(FAMILY_ID, "fixes", "2026-07-19")).toBe(0);
      // Usage degrades to the caller's own uid partition instead (family-less handling).
      expect(await deps.usageRepo.get(USER_ID, "locationBatches", "2026-07-19")).toBe(1);
      expect(await deps.usageRepo.get(USER_ID, "fixes", "2026-07-19")).toBe(1);

      // (b) last-known and group fan-out still apply — only the family-scoped writes skip.
      expect(result.lastKnownUpdated).toBe(true);
      const stored = await deps.lastKnownRepo.get(USER_ID, DEVICE_ID);
      expect(stored?.lat).toBe(51.0543);
      const groupPosition = await deps.groupLastKnownRepo.get(GUARD_GROUP_ID, USER_ID);
      expect(groupPosition).not.toBeNull();
    });

    it("pays the extra family-existence read only when the caller HAD a family (not for an already family-less caller)", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      let readCount = 0;
      const realGetFamilyMeta = deps.familyRepo.getFamilyMeta.bind(deps.familyRepo);
      deps.familyRepo.getFamilyMeta = async (familyId: string) => {
        readCount += 1;
        return realGetFamilyMeta(familyId);
      };

      await reportLocations(baseInput({ familyId: null }), deps);

      expect(readCount).toBe(0);
    });

    it("does not affect the happy path: an accepted batch for a family that still exists appends history and records family-keyed usage as before", async () => {
      const deps = buildDeps();
      seedDevice(deps);

      await reportLocations(baseInput(), deps);

      expect(deps.historyStore.fixes.length).toBe(1);
      expect(await deps.usageRepo.get(FAMILY_ID, "locationBatches", "2026-07-19")).toBe(1);
    });
  });

  // B18 security review-gate follow-up (Major, 002 §4.2): the §1.2 ownership check earlier
  // in this function is a snapshot taken BEFORE this request's writes; a concurrent
  // DELETE /users/me (001 §13.2) deletes the whole Devices partition FIRST, but a request
  // already past that check would otherwise still write LastKnown/a marker/group
  // positions/history for an account being erased. Unlike the family guard above, there is
  // NO degraded-but-valid mode: the whole batch must be abandoned, nothing written.
  describe("write-time device-existence guard (002 §4.2, in-flight erasure race, B18 follow-up)", () => {
    // Simulates the account's Devices partition being wiped in the exact window between the
    // request's initial §1.2 ownership read and this guard's own re-read: wraps the fake's
    // getDevice so the SECOND call (the guard's, not the earlier ownership check's first
    // call) deletes the row before resolving — mirrors raceFamilyDeletionIntoGuardRead above.
    function raceDeviceDeletionIntoGuardRead(deps: ReturnType<typeof buildDeps>): void {
      const realGetDevice = deps.deviceRepo.getDevice.bind(deps.deviceRepo);
      let callCount = 0;
      deps.deviceRepo.getDevice = async (ownerUserId: string, deviceId: string) => {
        callCount += 1;
        if (callCount === 2) {
          await deps.deviceRepo.deleteDevicesByOwner(ownerUserId);
        }
        return realGetDevice(ownerUserId, deviceId);
      };
    }

    it("abandons the WHOLE batch — no marker, no last-known, no group position, no history, no usage — when the device is gone by write time", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      const GUARD_GROUP_ID = "grp_9J2Kq7Lm3NpR5sTvWxYz";
      await seedActiveGroupMembership(deps, GUARD_GROUP_ID);
      raceDeviceDeletionIntoGuardRead(deps);

      await expectAppError(reportLocations(baseInput(), deps), "DEVICE_NOT_FOUND");

      // Nothing was written — not last-known, not the group position, not history, not usage,
      // and the idempotency marker is still free (a genuine retry after re-registration must
      // not be shadowed by a marker this abandoned attempt should never have written).
      expect(await deps.lastKnownRepo.get(USER_ID, DEVICE_ID)).toBeNull();
      expect(await deps.groupLastKnownRepo.get(GUARD_GROUP_ID, USER_ID)).toBeNull();
      expect(deps.historyStore.fixes).toEqual([]);
      expect(await deps.usageRepo.get(FAMILY_ID, "locationBatches", "2026-07-19")).toBe(0);
      expect(await deps.usageRepo.get(USER_ID, "locationBatches", "2026-07-19")).toBe(0);
      const stillInsertable = await deps.idempotencyRepo.tryInsertBatchMarker(DEVICE_ID, "b7f2c1d0-0000-4000-8000-000000000001", {
        receivedAt: "x",
        fixCount: 1,
      });
      expect(stillInsertable).toBe(true);
    });

    it("does not affect the happy path: a device that still exists at write time is unaffected", async () => {
      const deps = buildDeps();
      seedDevice(deps);

      const result = await reportLocations(baseInput(), deps);

      expect(result.accepted).toBe(1);
      expect(result.lastKnownUpdated).toBe(true);
    });
  });

  // specs/001 §5.1 group fan-out side effect + specs/002 §2.12 GroupLastKnown. Active-only,
  // position-only, only-newer — mirrors the family LastKnown semantics but independently.
  describe("group fan-out (001 §5.1, 002 §2.12)", () => {
    const GROUP_ID = "grp_9J2Kq7Lm3NpR5sTvWxYz";

    it("upserts a position-only GroupLastKnown row into the reporter's active group", async () => {
      const deps = buildDeps();
      seedDevice(deps, { syncIntervalMinutes: 15 });
      await seedActiveGroupMembership(deps, GROUP_ID);

      await reportLocations(baseInput(), deps);

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(stored).toEqual({
        userId: USER_ID,
        lat: 51.0543,
        lon: 3.7174,
        accuracyM: 12.5,
        recordedAt: "2026-07-19T09:00:00Z",
        receivedAt: new Date(NOW).toISOString(),
        syncIntervalMinutes: 15,
      });
    });

    it("never includes deviceId, batteryPct, or source (position-only, 005 §3)", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID);

      await reportLocations(baseInput(), deps);

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(Object.keys(stored as object).sort()).toEqual(
        ["accuracyM", "lat", "lon", "recordedAt", "receivedAt", "syncIntervalMinutes", "userId"].sort(),
      );
    });

    it("fans out to every one of the reporter's active groups", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, "grp_a");
      await seedActiveGroupMembership(deps, "grp_b");

      await reportLocations(baseInput(), deps);

      expect(await deps.groupLastKnownRepo.get("grp_a", USER_ID)).not.toBeNull();
      expect(await deps.groupLastKnownRepo.get("grp_b", USER_ID)).not.toBeNull();
    });

    it("does NOT fan out to a grace-state (ended) group", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID, {
        endsAt: "2026-07-18T00:00:00Z", // 1 day before NOW, grace 7 days -> "ended"
        expiryPolicy: "grace",
      });

      await reportLocations(baseInput(), deps);

      expect(await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID)).toBeNull();
    });

    it("does NOT fan out to an archived group", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID, {
        endsAt: "2026-01-01T00:00:00Z",
        expiryPolicy: "archive",
      });

      await reportLocations(baseInput(), deps);

      expect(await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID)).toBeNull();
    });

    it("does NOT fan out to an expired (delete-policy, past endsAt) group", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID, {
        endsAt: "2026-01-01T00:00:00Z",
        expiryPolicy: "delete",
      });

      await reportLocations(baseInput(), deps);

      expect(await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID)).toBeNull();
    });

    it("tolerates an orphaned reverse-index row (group meta missing — self-healing skip)", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await deps.userRepo.addGroupMembership(USER_ID, {
        groupId: "grp_gone",
        role: "owner",
        joinedAt: NOW,
      });

      await expect(reportLocations(baseInput(), deps)).resolves.toMatchObject({ accepted: 1 });
    });

    it("only-newer: does not overwrite a group position that is already newer than the incoming fix", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID);
      deps.groupLastKnownRepo.seed(GROUP_ID, {
        userId: USER_ID,
        lat: 10,
        lon: 10,
        accuracyM: 5,
        recordedAt: "2026-07-19T09:30:00Z", // newer than the fix's 09:00:00Z
        receivedAt: "2026-07-19T09:30:02Z",
        syncIntervalMinutes: 15,
      });

      await reportLocations(baseInput(), deps);

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(stored?.lat).toBe(10); // unchanged
    });

    it("only-newer: does overwrite when the incoming fix is newer", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID);
      deps.groupLastKnownRepo.seed(GROUP_ID, {
        userId: USER_ID,
        lat: 10,
        lon: 10,
        accuracyM: 5,
        recordedAt: "2026-07-19T08:00:00Z", // older than the fix's 09:00:00Z
        receivedAt: "2026-07-19T08:00:02Z",
        syncIntervalMinutes: 15,
      });

      await reportLocations(baseInput(), deps);

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(stored?.lat).toBe(51.0543);
    });

    it("uses the batch's newest fix, not the last array element", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID);

      await reportLocations(
        baseInput({
          body: {
            batchId: "b7f2c1d0-0000-4000-8000-000000000001",
            fixes: [
              fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001", recordedAt: "2026-07-19T09:05:00Z", lat: 52.0 }),
              fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T09:00:00Z", lat: 51.0 }),
            ],
          },
        }),
        deps,
      );

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(stored?.lat).toBe(52.0);
      expect(stored?.recordedAt).toBe("2026-07-19T09:05:00Z");
    });

    it("freezes the reporting device's CURRENT syncIntervalMinutes into the group position", async () => {
      const deps = buildDeps();
      seedDevice(deps, { syncIntervalMinutes: 30 });
      await seedActiveGroupMembership(deps, GROUP_ID);

      await reportLocations(baseInput(), deps);

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(stored?.syncIntervalMinutes).toBe(30);
    });

    it("does not fan out for a duplicate (replayed) batch", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID);
      const body = {
        batchId: "b7f2c1d0-0000-4000-8000-000000000001",
        fixes: [fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000001" })],
      };
      await reportLocations(baseInput({ body }), deps);
      deps.groupLastKnownRepo.seed(GROUP_ID, {
        userId: USER_ID,
        lat: 999,
        lon: 999,
        accuracyM: 1,
        recordedAt: "2026-07-19T09:00:00Z",
        receivedAt: "2026-07-19T09:00:02Z",
        syncIntervalMinutes: 15,
      });

      await reportLocations(baseInput({ body }), deps); // replay — no marker inserted

      const stored = await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID);
      expect(stored?.lat).toBe(999); // untouched by the replay
    });

    it("still fans out for a family-less caller (groups don't require a family, 001 §5.1)", async () => {
      const deps = buildDeps();
      seedDevice(deps);
      await seedActiveGroupMembership(deps, GROUP_ID);

      await reportLocations(baseInput({ familyId: null }), deps);

      expect(await deps.groupLastKnownRepo.get(GROUP_ID, USER_ID)).not.toBeNull();
    });

    it("does not fan out at all for a caller with no group memberships", async () => {
      const deps = buildDeps();
      seedDevice(deps);

      await expect(reportLocations(baseInput(), deps)).resolves.toMatchObject({ accepted: 1 });
      // No assertion possible on "no groups written" beyond absence — covered implicitly by
      // every other test asserting presence only when a membership was actually seeded.
    });
  });
});
