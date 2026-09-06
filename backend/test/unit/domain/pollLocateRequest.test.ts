import { describe, expect, it } from "vitest";
import { pollLocateRequest } from "../../../src/domain/locate/pollLocateRequest";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryLocateRequestRepo } from "../../fakes/inMemoryLocateRequestRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { LocateRequestRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const REQUESTER_UID = "u1";
const OTHER_UID = "u3";
const REQUEST_ID = "lr_00000000000000000001";
const TARGET_DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const NOW = "2026-07-19T09:10:00Z";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  return {
    locateRequestRepo: new InMemoryLocateRequestRepo(),
    entitlementsRepo,
    clock: new FixedClock(new Date(NOW)),
  };
}

function record(overrides: Partial<LocateRequestRecord> = {}): LocateRequestRecord {
  return {
    requestId: REQUEST_ID,
    familyId: FAMILY_ID,
    targetUserId: "u2",
    targetDeviceId: TARGET_DEVICE_ID,
    requestedBy: REQUESTER_UID,
    status: "pending",
    createdAt: "2026-07-19T09:09:00Z",
    expiresAt: "2026-07-19T09:10:00Z",
    ...overrides,
  };
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    uid: REQUESTER_UID,
    familyId: FAMILY_ID as string | null,
    requestId: REQUEST_ID,
    ...overrides,
  };
}

describe("domain/locate/pollLocateRequest", () => {
  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();
    await expectAppError(pollLocateRequest(baseInput({ familyId: null }), deps), "FAMILY_NOT_FOUND");
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record());
    const entitlementsRepo = new InMemoryEntitlementsRepo();
    await expectAppError(pollLocateRequest(baseInput(), { ...deps, entitlementsRepo }), "INTERNAL_ERROR");
  });

  it("throws LOCATE_REQUEST_NOT_FOUND for an unknown requestId", async () => {
    const deps = buildDeps();
    await expectAppError(pollLocateRequest(baseInput(), deps), "LOCATE_REQUEST_NOT_FOUND");
  });

  it("throws AUTH_FORBIDDEN when the caller is not the original requester", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ requestedBy: REQUESTER_UID }));
    await expectAppError(pollLocateRequest(baseInput({ uid: OTHER_UID }), deps), "AUTH_FORBIDDEN");
  });

  it("returns pending status with null fix before expiry", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: "2026-07-19T09:11:00Z" }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pending");
    expect(result.fix).toBeNull();
    expect(result.expiresAt).toBe("2026-07-19T09:11:00Z");
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("carries createdAt through, and reports fulfilledAt null / late false on a pending request (specs/001 §6.2 amended 2026-09-06)", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(
      record({ status: "pending", createdAt: "2026-07-19T09:09:00Z", expiresAt: "2026-07-19T09:11:00Z" }),
    );

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.createdAt).toBe("2026-07-19T09:09:00Z");
    expect(result.fulfilledAt).toBeNull();
    expect(result.late).toBe(false);
  });

  it("reports fulfilledAt and late:true for a request fulfilled inside the grace window", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(
      record({
        status: "fulfilled",
        expiresAt: "2026-07-19T09:09:00Z",
        fulfilledAt: "2026-07-19T09:09:45Z",
        late: true,
      }),
    );

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
    expect(result.fulfilledAt).toBe("2026-07-19T09:09:45Z");
    expect(result.late).toBe(true);
  });

  it("lazily flips pending -> expired in place when polled past expiresAt", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: "2026-07-19T09:09:59Z" }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("expired");
    const stored = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    expect(stored?.status).toBe("expired");
  });

  it("does not flip to expired exactly at expiresAt (boundary: only strictly past expires)", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ status: "pending", expiresAt: NOW }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pending");
  });

  it("returns the fix (plus deviceId) when the request is fulfilled", async () => {
    const deps = buildDeps();
    const fixJson = JSON.stringify({
      fixId: "a1e2b3c4-0000-4000-8000-000000000001",
      recordedAt: "2026-07-19T09:09:30Z",
      lat: 51.0544,
      lon: 3.717,
      accuracyM: 4.8,
      batteryPct: 77,
      source: "locate",
    });
    deps.locateRequestRepo.seed(record({ status: "fulfilled", fixJson }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("fulfilled");
    expect(result.fix).toEqual({
      fixId: "a1e2b3c4-0000-4000-8000-000000000001",
      recordedAt: "2026-07-19T09:09:30Z",
      lat: 51.0544,
      lon: 3.717,
      accuracyM: 4.8,
      batteryPct: 77,
      source: "locate",
      deviceId: TARGET_DEVICE_ID,
    });
  });

  it("returns null fix for an expired request (never fulfilled)", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ status: "expired" }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("expired");
    expect(result.fix).toBeNull();
  });

  it("returns null fix for a pushFailed request", async () => {
    const deps = buildDeps();
    deps.locateRequestRepo.seed(record({ status: "pushFailed", expiresAt: "2026-07-19T09:11:00Z" }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pushFailed");
    expect(result.fix).toBeNull();
  });

  it("does not lazily flip a non-pending status to expired, even past expiresAt", async () => {
    const deps = buildDeps();
    // pushFailed (terminal) with an expiresAt already in the past: must stay pushFailed,
    // not be reclassified as expired (the lazy-expiry rule only ever applies to "pending").
    deps.locateRequestRepo.seed(record({ status: "pushFailed", expiresAt: "2026-07-19T09:09:00Z" }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pushFailed");
    const stored = await deps.locateRequestRepo.get(FAMILY_ID, REQUEST_ID);
    expect(stored?.status).toBe("pushFailed");
  });

  it("never returns a fix unless status is actually fulfilled, even if fixJson happens to be set", async () => {
    // Defensive: the domain never produces this combination itself, but the poll guard
    // must key off `status`, not merely the presence of fixJson.
    const deps = buildDeps();
    const fixJson = JSON.stringify({
      fixId: "a1e2b3c4-0000-4000-8000-000000000001",
      recordedAt: "2026-07-19T09:09:30Z",
      lat: 51.0544,
      lon: 3.717,
      accuracyM: 4.8,
      batteryPct: 77,
      source: "locate",
    });
    deps.locateRequestRepo.seed(record({ status: "expired", fixJson }));

    const result = await pollLocateRequest(baseInput(), deps);

    expect(result.status).toBe("expired");
    expect(result.fix).toBeNull();
  });
});
