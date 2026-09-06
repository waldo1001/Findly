import { describe, expect, it } from "vitest";
import { fulfillLocateRequest, toStoredFix } from "../../../src/domain/locate/fulfillLocateRequest";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryLocateRequestRepo } from "../../fakes/inMemoryLocateRequestRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";
import { InMemoryHistoryStore } from "../../fakes/inMemoryHistoryStore";
import { InMemoryIdempotencyRepo } from "../../fakes/inMemoryIdempotencyRepo";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord, LocateRequestRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const TARGET_UID = "u2";
const ATTACKER_UID = "u3";
const TARGET_DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const OTHER_DEVICE_ID = "4f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2c";
const UNREGISTERED_DEVICE_ID = "5a2b4c1e-8d3f-4a9b-bc4d-9e6f5a4b3c2d";
const REQUEST_ID = "lr_00000000000000000001";
const NOW = "2026-07-19T09:10:00Z";

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: TARGET_DEVICE_ID,
    ownerUserId: TARGET_UID,
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Noor's phone",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    ...overrides,
  };
}

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  const deviceRepo = new InMemoryDeviceRepo();
  // Default: the request's actual target device, correctly registered to its real owner.
  deviceRepo.seed(TARGET_UID, device());
  return {
    deviceRepo,
    locateRequestRepo: new InMemoryLocateRequestRepo(),
    lastKnownRepo: new InMemoryLastKnownRepo(),
    historyStore: new InMemoryHistoryStore(),
    idempotencyRepo: new InMemoryIdempotencyRepo(),
    usageRepo: new InMemoryUsageRepo(),
    entitlementsRepo,
    clock: new FixedClock(new Date(NOW)),
  };
}

function record(overrides: Partial<LocateRequestRecord> = {}): LocateRequestRecord {
  return {
    requestId: REQUEST_ID,
    familyId: FAMILY_ID,
    targetUserId: TARGET_UID,
    targetDeviceId: TARGET_DEVICE_ID,
    requestedBy: "u1",
    status: "pending",
    createdAt: "2026-07-19T09:09:00Z",
    expiresAt: "2026-07-19T09:10:00Z",
    ...overrides,
  };
}

function fix(overrides: Record<string, unknown> = {}) {
  return {
    fixId: "a1e2b3c4-0000-4000-8000-000000000001",
    recordedAt: "2026-07-19T09:09:30Z",
    lat: 51.0544,
    lon: 3.717,
    accuracyM: 4.8,
    batteryPct: 77,
    source: "locate",
    ...overrides,
  };
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    uid: TARGET_UID,
    familyId: FAMILY_ID as string | null,
    deviceId: TARGET_DEVICE_ID as string | null,
    requestId: REQUEST_ID,
    body: { fix: fix() },
    ...overrides,
  };
}

describe("domain/locate/toStoredFix", () => {
  it("omits absent optional fields as missing keys, not undefined-valued ones", () => {
    const result = toStoredFix(fix() as Parameters<typeof toStoredFix>[0]);

    expect("altitudeM" in result).toBe(false);
    expect("speedMps" in result).toBe(false);
    expect("bearingDeg" in result).toBe(false);
    expect(result.fixId).toBe("a1e2b3c4-0000-4000-8000-000000000001");
    expect(result.source).toBe("locate");
  });

  it("includes optional fields with their actual values when present", () => {
    const result = toStoredFix(
      fix({ altitudeM: 8.0, speedMps: 1.5, bearingDeg: 90 }) as Parameters<typeof toStoredFix>[0],
    );

    expect(result.altitudeM).toBe(8.0);
    expect(result.speedMps).toBe(1.5);
    expect(result.bearingDeg).toBe(90);
  });
});

describe("domain/locate/fulfillLocateRequest", () => {
  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();
    await expectAppError(fulfillLocateRequest(baseInput({ familyId: null }), deps), "FAMILY_NOT_FOUND");
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));
    const entitlementsRepo = new InMemoryEntitlementsRepo();
    await expectAppError(fulfillLocateRequest(baseInput(), { ...deps, entitlementsRepo }), "INTERNAL_ERROR");
  });

  it("throws LOCATE_REQUEST_NOT_FOUND for an unknown requestId", async () => {
    const deps = buildDeps();
    await expectAppError(fulfillLocateRequest(baseInput(), deps), "LOCATE_REQUEST_NOT_FOUND");
  });

  it("throws AUTH_FORBIDDEN when X-Device-Id does not match the request's targetDeviceId (but IS a device the caller owns)", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));
    // The caller's own second device — legitimately registered to them, just not the
    // one this locate request targeted. Must be AUTH_FORBIDDEN, not DEVICE_NOT_FOUND.
    deps.deviceRepo.seed(TARGET_UID, device({ deviceId: OTHER_DEVICE_ID, ownerUserId: TARGET_UID }));
    await expectAppError(
      fulfillLocateRequest(baseInput({ deviceId: OTHER_DEVICE_ID }), deps),
      "AUTH_FORBIDDEN",
    );
  });

  it("throws AUTH_FORBIDDEN when X-Device-Id header is missing", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));
    await expectAppError(fulfillLocateRequest(baseInput({ deviceId: null }), deps), "AUTH_FORBIDDEN");
  });

  it("throws DEVICE_NOT_FOUND when X-Device-Id is not a registered device at all (specs/001 §1.2)", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ targetDeviceId: UNREGISTERED_DEVICE_ID, expiresAt: "2026-07-19T09:11:00Z" }));
    await expectAppError(
      fulfillLocateRequest(baseInput({ deviceId: UNREGISTERED_DEVICE_ID }), deps),
      "DEVICE_NOT_FOUND",
    );
  });

  it("SECURITY: throws DEVICE_NOT_FOUND when X-Device-Id equals the request's target but is owned by a DIFFERENT user than the caller", async () => {
    // Exploit scenario: an attacker learns the victim's deviceId (e.g. via GET
    // /locations/latest or the create-locate-request response) and calls fulfill with
    // THEIR OWN token but X-Device-Id set to the victim's device, trying to inject a
    // forged fix into the victim's LastKnown/history. Ownership must block this before
    // the §6.3 target-match check is ever reached.
    const deps = buildDeps(); // TARGET_DEVICE_ID is registered to TARGET_UID, not ATTACKER_UID
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    await expectAppError(
      fulfillLocateRequest(baseInput({ uid: ATTACKER_UID, deviceId: TARGET_DEVICE_ID }), deps),
      "DEVICE_NOT_FOUND",
    );

    // And no forged fix was written anywhere.
    expect(await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID)).toBeNull();
    expect(deps.historyStore.fixes.length).toBe(0);
  });

  it("throws DEVICE_NOT_FOUND when the caller's own partition holds a mismatched-owner row (002 §2.4 data-integrity defense-in-depth)", async () => {
    // Deliberately seeded under the CALLER's own partition (TARGET_UID) but with a
    // different ownerUserId field — structurally shouldn't happen (every write keys by
    // its own ownerUserId), kept as a belt-and-suspenders check alongside the SECURITY
    // test above (which relies on partition isolation itself, not this field check).
    const deps = buildDeps();
    deps.deviceRepo.seed(TARGET_UID, device({ ownerUserId: "someone-else" }));
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    await expectAppError(fulfillLocateRequest(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("legit path: caller owns the device AND it equals targetDeviceId -> succeeds", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    const result = await fulfillLocateRequest(baseInput({ uid: TARGET_UID, deviceId: TARGET_DEVICE_ID }), deps);

    expect(result.status).toBe("fulfilled");
  });

  it("throws VALIDATION_FAILED when fix.source is not 'locate'", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));
    await expectAppError(
      fulfillLocateRequest(baseInput({ body: { fix: fix({ source: "periodic" }) } }), deps),
      "VALIDATION_FAILED",
    );
  });

  it("within the window: marks the request fulfilled and returns status fulfilled, late:false", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    const result = await fulfillLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
    expect(result.late).toBe(false);
    expect(result.features).toEqual(getFeatures("free"));
    const stored = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    expect(stored?.status).toBe("fulfilled");
    expect(stored?.fulfilledAt).toBe(new Date(NOW).toISOString());
    expect(stored?.late).toBe(false);
  });

  it("updates last-known and appends history exactly like a §5.1 report", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    await fulfillLocateRequest(baseInput(), deps);

    const stored = await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID);
    expect(stored?.lat).toBe(51.0544);
    expect(stored?.lon).toBe(3.717);
    expect(stored?.accuracyM).toBe(4.8);
    expect(stored?.batteryPct).toBe(77);
    expect(stored?.source).toBe("locate");
    expect(stored?.recordedAt).toBe("2026-07-19T09:09:30Z");
    // Omitted (not null) when absent from the submitted fix — same rule as §5.1.
    expect("altitudeM" in (stored as object)).toBe(false);
    expect("speedMps" in (stored as object)).toBe(false);
    expect("bearingDeg" in (stored as object)).toBe(false);

    expect(deps.historyStore.fixes.length).toBe(1);
    const appended = deps.historyStore.fixes[0]!;
    expect(appended.familyId).toBe(FAMILY_ID);
    expect(appended.userId).toBe(TARGET_UID);
    expect(appended.deviceId).toBe(TARGET_DEVICE_ID);
    expect(appended.fix.fixId).toBe("a1e2b3c4-0000-4000-8000-000000000001");
    expect(appended.fix.lat).toBe(51.0544);
    expect(appended.fix.lon).toBe(3.717);
    expect(appended.fix.accuracyM).toBe(4.8);
    expect(appended.fix.batteryPct).toBe(77);
    expect(appended.fix.source).toBe("locate");
    expect("altitudeM" in appended.fix).toBe(false);
    expect("speedMps" in appended.fix).toBe(false);
    expect("bearingDeg" in appended.fix).toBe(false);

    const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    const storedFix = JSON.parse(requestRecord!.fixJson!) as Record<string, unknown>;
    expect(storedFix.fixId).toBe("a1e2b3c4-0000-4000-8000-000000000001");
    expect(storedFix.lat).toBe(51.0544);
    expect(storedFix.lon).toBe(3.717);
    expect(storedFix.accuracyM).toBe(4.8);
    expect(storedFix.batteryPct).toBe(77);
    expect(storedFix.source).toBe("locate");
    expect("altitudeM" in storedFix).toBe(false);
    expect("speedMps" in storedFix).toBe(false);
    expect("bearingDeg" in storedFix).toBe(false);
  });

  it("does not overwrite last-known with an older fix (only-newer rule)", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));
    deps.lastKnownRepo.seed(TARGET_UID, {
      deviceId: TARGET_DEVICE_ID,
      lat: 10,
      lon: 20,
      accuracyM: 5,
      batteryPct: 90,
      recordedAt: "2026-07-19T09:09:59Z", // newer than the fulfill fix's 09:09:30
      receivedAt: "2026-07-19T09:09:59Z",
      source: "periodic",
    });

    await fulfillLocateRequest(baseInput(), deps);

    const stored = await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID);
    expect(stored?.lat).toBe(10);
  });

  it("carries optional altitudeM/speedMps/bearingDeg through to last-known, history, and the stored fix when present", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    await fulfillLocateRequest(
      baseInput({ body: { fix: fix({ altitudeM: 8.0, speedMps: 1.5, bearingDeg: 90 }) } }),
      deps,
    );

    const stored = await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID);
    expect(stored?.altitudeM).toBe(8.0);
    expect(stored?.speedMps).toBe(1.5);
    expect(stored?.bearingDeg).toBe(90);

    const appended = deps.historyStore.fixes[0]!;
    expect(appended.fix.altitudeM).toBe(8.0);
    expect(appended.fix.speedMps).toBe(1.5);
    expect(appended.fix.bearingDeg).toBe(90);

    const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    const storedFix = JSON.parse(requestRecord!.fixJson!) as Record<string, unknown>;
    expect(storedFix.altitudeM).toBe(8.0);
    expect(storedFix.speedMps).toBe(1.5);
    expect(storedFix.bearingDeg).toBe(90);
  });

  it("a DIFFERENT fixId on an already-fulfilled request does not throw, even past expiresAt: stored as history but does not replace fixJson (specs/001 §6.3 amended 2026-09-06)", async () => {
    const deps = buildDeps();
    const priorFixJson = JSON.stringify({ ...fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000099" }) });
    deps.locateRequestRepo.seed(
      record({
        status: "fulfilled",
        expiresAt: "2026-07-19T09:09:00Z",
        fixJson: priorFixJson,
        fulfilledAt: "2026-07-19T09:09:00Z",
        late: false,
      }),
    );

    const result = await fulfillLocateRequest(
      baseInput({ body: { fix: fix({ fixId: "a1e2b3c4-0000-4000-8000-000000000002" }) } }),
      deps,
    );

    expect(result.status).toBe("fulfilled");
    expect(result.late).toBe(false); // unchanged — the ORIGINAL fulfil's late value

    const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    expect(requestRecord?.status).toBe("fulfilled"); // must NOT be clobbered to "expired"
    expect(requestRecord?.fixJson).toBe(priorFixJson); // NOT replaced by the different fixId

    // But it IS stored as history/last-known, same as any other accepted fix (idempotent-on-fixId dedupe).
    expect(deps.historyStore.fixes.length).toBe(1);
    const stored = await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID);
    expect(stored?.lat).toBe(51.0544);
  });

  it("the SAME fixId replayed against an already-fulfilled request is idempotent, even long past expiresAt", async () => {
    const deps = buildDeps();
    const priorFixJson = JSON.stringify({ ...fix() }); // same fixId as baseInput()'s fix
    deps.locateRequestRepo.seed(
      record({
        status: "fulfilled",
        expiresAt: "2026-07-19T08:00:00Z", // far in the past, well outside any grace window
        fixJson: priorFixJson,
        fulfilledAt: "2026-07-19T08:00:30Z",
        late: true,
      }),
    );
    // The marker for this fixId was already inserted by the original fulfil.
    await deps.idempotencyRepo.tryInsertFixMarker(TARGET_DEVICE_ID, fix().fixId as string, "2026-07-19T08:00:30Z");

    const result = await fulfillLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
    expect(result.late).toBe(true); // the ORIGINAL late value, not recomputed against "now"
    const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    expect(requestRecord?.fixJson).toBe(priorFixJson);
  });

  it("defaults late to false for an already-fulfilled request whose stored late field was never set (legacy/undefined)", async () => {
    const deps = buildDeps();
    const priorFixJson = JSON.stringify({ ...fix() }); // same fixId as baseInput()'s fix
    const seeded = record({
      status: "fulfilled",
      expiresAt: "2026-07-19T09:11:00Z",
      fixJson: priorFixJson,
      fulfilledAt: "2026-07-19T09:09:30Z",
      // `late` deliberately omitted (undefined) — must fall back to false, not true.
    });
    delete seeded.late;
    deps.locateRequestRepo.seed(seeded);
    await deps.idempotencyRepo.tryInsertFixMarker(TARGET_DEVICE_ID, fix().fixId as string, "2026-07-19T09:09:30Z");

    const result = await fulfillLocateRequest(baseInput(), deps);

    expect(result.late).toBe(false);
  });

  it("increments fixes usage on an accepted fulfill", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    await fulfillLocateRequest(baseInput(), deps);

    expect(await deps.usageRepo.get(FAMILY_ID, "fixes", "2026-07-19")).toBe(1);
  });

  it("is idempotent on fixId: a replay does not double-write last-known/history/fixes usage, and returns the same late value", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    const first = await fulfillLocateRequest(baseInput(), deps);
    const result = await fulfillLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
    expect(result.late).toBe(first.late);
    expect(deps.historyStore.fixes.length).toBe(1);
    expect(await deps.usageRepo.get(FAMILY_ID, "fixes", "2026-07-19")).toBe(1);
  });

  it("does not flip to expired exactly at expiresAt (boundary: only strictly past expires), late:false", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: NOW }));

    const result = await fulfillLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
    expect(result.late).toBe(false);
  });

  describe("grace window (specs/001 §6.3 amended 2026-09-06)", () => {
    it("a fulfil 1 second past expiresAt is accepted as fulfilled, late:true, and stores fixJson/fulfilledAt", async () => {
      const deps = buildDeps();
      deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: "2026-07-19T09:09:59Z" }));

      const result = await fulfillLocateRequest(baseInput(), deps);

      expect(result.status).toBe("fulfilled");
      expect(result.late).toBe(true);
      const stored = await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID);
      expect(stored?.lat).toBe(51.0544);
      expect(deps.historyStore.fixes.length).toBe(1);

      const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
      expect(requestRecord?.status).toBe("fulfilled");
      expect(requestRecord?.late).toBe(true);
      expect(requestRecord?.fulfilledAt).toBe(new Date(NOW).toISOString());
      expect(requestRecord?.fixJson).toBeTruthy();
    });

    it("flips an already lazily-expired request to fulfilled when the fulfil arrives inside the grace window", async () => {
      const deps = buildDeps();
      deps.locateRequestRepo.seed(record({ status: "expired", expiresAt: "2026-07-19T09:09:59Z" }));

      const result = await fulfillLocateRequest(baseInput(), deps);

      expect(result.status).toBe("fulfilled");
      expect(result.late).toBe(true);
      const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
      expect(requestRecord?.status).toBe("fulfilled");
    });

    it("accepts a fulfil exactly at the 10-minute grace boundary (now == expiresAt + 10min)", async () => {
      const deps = buildDeps();
      // expiresAt + 10min === NOW exactly.
      deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: "2026-07-19T09:00:00Z" }));

      const result = await fulfillLocateRequest(baseInput(), deps);

      expect(result.status).toBe("fulfilled");
      expect(result.late).toBe(true);
    });

    it("rejects a fulfil 1 second past the 10-minute grace boundary: 410, fix still stored, status stays expired", async () => {
      const deps = buildDeps();
      // expiresAt + 10min is 1 second before NOW.
      deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: "2026-07-19T08:59:59Z" }));

      await expectAppError(fulfillLocateRequest(baseInput(), deps), "LOCATE_REQUEST_EXPIRED");

      const stored = await deps.lastKnownRepo.get(TARGET_UID, TARGET_DEVICE_ID);
      expect(stored?.lat).toBe(51.0544);
      expect(deps.historyStore.fixes.length).toBe(1);

      const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
      expect(requestRecord?.status).toBe("expired");
      expect(requestRecord?.fixJson).toBeFalsy();
    });

    it("a fulfil more than 10 minutes past expiresAt on an ALREADY-expired request throws 410 without re-flipping status, and does not even re-write it", async () => {
      const deps = buildDeps();
      deps.locateRequestRepo.seed(record({ status: "expired", expiresAt: "2026-07-19T08:59:59Z" }));

      // Distinguishes "only re-writes when status was pending" from "always (re-)writes
      // expired regardless of prior status" — both produce the same final stored value
      // here, so the write-call-count itself is the only observable difference.
      let updateCalls = 0;
      const originalUpdate = deps.locateRequestRepo.update.bind(deps.locateRequestRepo);
      deps.locateRequestRepo.update = async (familyId, requestId, patch) => {
        updateCalls++;
        return originalUpdate(familyId, requestId, patch);
      };

      await expectAppError(fulfillLocateRequest(baseInput(), deps), "LOCATE_REQUEST_EXPIRED");

      const requestRecord = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
      expect(requestRecord?.status).toBe("expired");
      expect(updateCalls).toBe(0);
    });
  });

  it("a paused target device MAY still fulfill (TRACKING_PAUSED does not apply here)", async () => {
    // DeviceRepo IS consulted now (for the §1.2 ownership check), but trackingEnabled
    // is deliberately never inspected — a paused device must still be able to fulfill.
    const deps = buildDeps();
    deps.deviceRepo.seed(TARGET_UID, device({ trackingEnabled: false }));
    deps.locateRequestRepo.seed(record({ expiresAt: "2026-07-19T09:11:00Z" }));

    const result = await fulfillLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
  });

});
