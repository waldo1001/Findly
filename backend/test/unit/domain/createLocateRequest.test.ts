import { describe, expect, it } from "vitest";
import { createLocateRequest } from "../../../src/domain/locate/createLocateRequest";
import { getFeatures } from "../../../src/domain/plan";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryLastKnownRepo } from "../../fakes/inMemoryLastKnownRepo";
import { InMemoryLocateRequestRepo } from "../../fakes/inMemoryLocateRequestRepo";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FakePushSender } from "../../fakes/fakePushSender";
import { FixedClock } from "../../fakes/fixedClock";
import { SeqIdGenerator } from "../../fakes/seqIdGenerator";
import { expectAppError } from "../../support/expectAppError";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const REQUESTER_UID = "u1";
const TARGET_UID = "u2";
const DEVICE_A = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const DEVICE_B = "4f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2c";
const NOW = "2026-07-19T09:10:00Z";

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  const familyRepo = new InMemoryFamilyRepo();
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo,
    lastKnownRepo: new InMemoryLastKnownRepo(),
    locateRequestRepo: new InMemoryLocateRequestRepo(),
    usageRepo: new InMemoryUsageRepo(),
    entitlementsRepo,
    pushSender: new FakePushSender(),
    idGenerator: new SeqIdGenerator(),
    clock: new FixedClock(new Date(NOW)),
  };
}

async function seedFamily(deps: ReturnType<typeof buildDeps>): Promise<void> {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: REQUESTER_UID,
    createdAt: "2026-07-01T00:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: REQUESTER_UID,
    role: "parent",
    displayName: "Eric",
    joinedAt: "2026-07-01T00:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: TARGET_UID,
    role: "member",
    displayName: "Noor",
    joinedAt: "2026-07-01T00:00:00Z",
  });
}

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: DEVICE_A,
    ownerUserId: TARGET_UID,
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Noor's phone",
    pushToken: "fcm-token-a",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    ...overrides,
  };
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    uid: REQUESTER_UID,
    familyId: FAMILY_ID as string | null,
    body: { targetUserId: TARGET_UID },
    ...overrides,
  };
}

describe("domain/locate/createLocateRequest", () => {
  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();
    await expectAppError(createLocateRequest(baseInput({ familyId: null }), deps), "FAMILY_NOT_FOUND");
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());
    const entitlementsRepo = new InMemoryEntitlementsRepo(); // not seeded
    await expectAppError(
      createLocateRequest(baseInput(), { ...deps, entitlementsRepo }),
      "INTERNAL_ERROR",
    );
  });

  it("throws VALIDATION_FAILED when neither targetUserId nor targetDeviceId is present", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await expectAppError(createLocateRequest(baseInput({ body: {} }), deps), "VALIDATION_FAILED");
  });

  it("throws VALIDATION_FAILED when both targetUserId and targetDeviceId are present", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await expectAppError(
      createLocateRequest(baseInput({ body: { targetUserId: TARGET_UID, targetDeviceId: DEVICE_A } }), deps),
      "VALIDATION_FAILED",
    );
  });

  it("throws DEVICE_NOT_FOUND when the target user has no registered devices at all", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await expectAppError(createLocateRequest(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("throws TRACKING_PAUSED when the target user's devices exist but none are unpaused", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ trackingEnabled: false }));
    deps.deviceRepo.seed(TARGET_UID, device({ deviceId: DEVICE_B, trackingEnabled: false }));
    await expectAppError(createLocateRequest(baseInput(), deps), "TRACKING_PAUSED");
  });

  it("throws DEVICE_NOT_FOUND for an unknown targetDeviceId", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await expectAppError(
      createLocateRequest(baseInput({ body: { targetDeviceId: DEVICE_A } }), deps),
      "DEVICE_NOT_FOUND",
    );
  });

  it("throws TRACKING_PAUSED for a paused targetDeviceId", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ trackingEnabled: false }));
    await expectAppError(
      createLocateRequest(baseInput({ body: { targetDeviceId: DEVICE_A } }), deps),
      "TRACKING_PAUSED",
    );
  });

  it("creates a request directly via targetDeviceId when it is unpaused (distinct from the paused case)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ trackingEnabled: true }));

    const result = await createLocateRequest(baseInput({ body: { targetDeviceId: DEVICE_A } }), deps);

    expect(result.created).toBe(true);
    expect(result.targetUserId).toBe(TARGET_UID);
    expect(result.targetDeviceId).toBe(DEVICE_A);
  });

  it("resolves the SPECIFIC targetDeviceId requested among several fanned-out family devices, not just the first one found (002 §2.4 fan-out)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // DEVICE_A listed first in insertion order — the fan-out match must be by id, not
    // "whichever device happened to be first".
    deps.deviceRepo.seed(TARGET_UID, device({ deviceId: DEVICE_A, trackingEnabled: true }));
    deps.deviceRepo.seed(TARGET_UID, device({ deviceId: DEVICE_B, trackingEnabled: true }));

    const result = await createLocateRequest(baseInput({ body: { targetDeviceId: DEVICE_B } }), deps);

    expect(result.targetDeviceId).toBe(DEVICE_B);
  });

  it("does not treat a data-integrity mismatched-owner row in the target's own partition as a candidate (defense-in-depth)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // Stored under TARGET_UID's own partition, but the ownerUserId field disagrees —
    // structurally shouldn't happen (every write keys by its own ownerUserId).
    deps.deviceRepo.seed(TARGET_UID, device({ ownerUserId: "someone-else" }));

    await expectAppError(createLocateRequest(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("does not treat a stranger's device (not a member of this family) as a candidate — fan-out only visits the family's roster partitions (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    // A perfectly valid device, but owned by someone who is NOT in this family's roster.
    deps.deviceRepo.seed("stranger", device({ deviceId: DEVICE_A, ownerUserId: "stranger" }));

    await expectAppError(createLocateRequest(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("falls back to the raw uid for requestedByName when the requester isn't found in the roster", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    const result = await createLocateRequest(baseInput({ uid: "ghost-uid" }), deps);

    expect(result.created).toBe(true);
    expect(deps.pushSender.sent.length).toBe(1);
    expect(deps.pushSender.sent[0]!.data.requestedByName).toBe("ghost-uid");
  });

  it("creates a 201 pending request, returns instant lastKnown null when never reported, expiresAt = now+180s (specs/001 §6.1 amended 2026-09-06), createdAt = now", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.created).toBe(true);
    expect(result.status).toBe("pending");
    expect(result.targetUserId).toBe(TARGET_UID);
    expect(result.targetDeviceId).toBe(DEVICE_A);
    expect(result.requestId).toMatch(/^lr_[A-Za-z0-9]{20}$/);
    expect(result.createdAt).toBe(new Date(NOW).toISOString());
    expect(result.expiresAt).toBe(new Date(new Date(NOW).getTime() + 180_000).toISOString());
    expect(result.lastKnown).toBeNull();
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("coalesced (200) responses also carry the ORIGINAL request's createdAt, not the coalescing call's time", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());

    const first = await createLocateRequest(baseInput(), deps);
    deps.clock.set(new Date("2026-07-19T09:10:30Z"));
    const second = await createLocateRequest(baseInput(), deps);

    expect(second.created).toBe(false);
    expect(second.createdAt).toBe(first.createdAt);
    expect(second.createdAt).toBe(new Date(NOW).toISOString());
  });

  it("returns the instant lastKnown answer when the target device has reported before", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());
    deps.lastKnownRepo.seed(TARGET_UID, {
      deviceId: DEVICE_A,
      lat: 51.0543,
      lon: 3.7174,
      accuracyM: 15.0,
      batteryPct: 80,
      recordedAt: "2026-07-19T08:50:12Z",
      receivedAt: "2026-07-19T08:50:14Z",
      source: "periodic",
    });

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.lastKnown).toEqual({
      deviceId: DEVICE_A,
      lat: 51.0543,
      lon: 3.7174,
      accuracyM: 15.0,
      recordedAt: "2026-07-19T08:50:12Z",
    });
  });

  it("prefers a candidate with a valid push token over a more-recently-seen candidate without one", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_A, pushToken: undefined, lastSeenAt: "2026-07-19T09:09:00Z" }),
    );
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_B, pushToken: "fcm-token-b", lastSeenAt: "2026-07-19T09:00:00Z" }),
    );

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.targetDeviceId).toBe(DEVICE_B);
    expect(result.status).toBe("pending");
  });

  it("within the preferred (valid-token) group, picks the most-recently-seen candidate", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_A, pushToken: "fcm-token-a", lastSeenAt: "2026-07-19T09:00:00Z" }),
    );
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_B, pushToken: "fcm-token-b", lastSeenAt: "2026-07-19T09:05:00Z" }),
    );

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.targetDeviceId).toBe(DEVICE_B);
  });

  it("on a lastSeenAt tie within a group, the earlier-listed device wins (strict >, not >=)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_A, pushToken: "fcm-token-a", lastSeenAt: "2026-07-19T09:00:00Z" }),
    );
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_B, pushToken: "fcm-token-b", lastSeenAt: "2026-07-19T09:00:00Z" }),
    );

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.targetDeviceId).toBe(DEVICE_A);
  });

  it("when no candidate has a valid token, picks the most-recently-seen among all unpaused candidates", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_A, pushToken: undefined, lastSeenAt: "2026-07-19T09:00:00Z" }),
    );
    deps.deviceRepo.seed(
      TARGET_UID,
      device({ deviceId: DEVICE_B, pushToken: undefined, lastSeenAt: "2026-07-19T09:05:00Z" }),
    );

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.targetDeviceId).toBe(DEVICE_B);
    expect(result.status).toBe("pushFailed");
  });

  it("a candidate whose token IS present but pushInvalid:true does not count as a valid token", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "stale-token", pushInvalid: true }));

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pushFailed");
    expect(deps.pushSender.sent.length).toBe(0); // never even attempted — already known invalid
  });

  it("creates as pushFailed without calling the pushSender when the chosen device has no token at all", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: undefined }));

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pushFailed");
    expect(deps.pushSender.sent.length).toBe(0);
  });

  it("sends the LOCATE_REQUEST push with requestId/requestedByName/expiresAt when the device has a valid token", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    const result = await createLocateRequest(baseInput(), deps);

    expect(deps.pushSender.sent.length).toBe(1);
    const sent = deps.pushSender.sent[0]!;
    expect(sent.token).toBe("fcm-token-a");
    expect(sent.type).toBe("LOCATE_REQUEST");
    expect(sent.data).toEqual({
      type: "LOCATE_REQUEST",
      requestId: result.requestId,
      requestedByName: "Eric",
      expiresAt: result.expiresAt,
    });
  });

  it("pushFailed path (invalidToken outcome) marks the device pushInvalid:true", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));
    deps.pushSender.setOutcome("invalidToken");

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pushFailed");
    const stored = await deps.deviceRepo.getDevice(TARGET_UID, DEVICE_A);
    expect(stored?.pushInvalid).toBe(true);
  });

  it("a transport 'error' outcome does not flip status away from pending (push is best-effort)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));
    deps.pushSender.setOutcome("error");

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pending");
  });

  it("coalesces with an existing pending request for the same target device, returning 200", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());

    const first = await createLocateRequest(baseInput(), deps);
    expect(first.created).toBe(true);

    const second = await createLocateRequest(baseInput(), deps);

    expect(second.created).toBe(false);
    expect(second.requestId).toBe(first.requestId);
    expect(second.expiresAt).toBe(first.expiresAt);
  });

  it("coalesced (200) requests are excluded from the locateRequests usage quota metric", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());

    await createLocateRequest(baseInput(), deps);
    await createLocateRequest(baseInput(), deps);
    await createLocateRequest(baseInput(), deps);

    expect(await deps.usageRepo.get(FAMILY_ID, "locateRequests", "2026-07-19")).toBe(1);
  });

  it("throws LIMIT_EXCEEDED with details.limit locateRequestsPerDay once the daily quota is reached", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());
    await deps.usageRepo.increment(FAMILY_ID, "locateRequests", "2026-07-19", 100); // free plan limit

    await expectAppError(createLocateRequest(baseInput(), deps), "LIMIT_EXCEEDED", {
      limit: "locateRequestsPerDay",
    });
  });

  it("allows a create at exactly one below the quota (boundary: only >= the limit blocks)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());
    await deps.usageRepo.increment(FAMILY_ID, "locateRequests", "2026-07-19", 99);

    const result = await createLocateRequest(baseInput(), deps);
    expect(result.created).toBe(true);
  });

  it("increments locateRequests usage exactly once on a 201 create", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device());

    await createLocateRequest(baseInput(), deps);

    expect(await deps.usageRepo.get(FAMILY_ID, "locateRequests", "2026-07-19")).toBe(1);
  });
});
