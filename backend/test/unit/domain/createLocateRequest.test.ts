import { describe, expect, it, vi } from "vitest";
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
import { expectNotificationTitle } from "../../support/expectPushMessage";
import type { DeviceRecord } from "../../../src/ports/repositories";
import { EMPTY_DISPLAY_NAME_FALLBACK } from "../../../src/domain/text/normalizeDisplayText";

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

  it("falls back to the §1.4 placeholder (never the raw uid) for requestedByName when the requester isn't found in the roster", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    const result = await createLocateRequest(baseInput({ uid: "ghost-uid" }), deps);

    expect(result.created).toBe(true);
    expect(deps.pushSender.sent.length).toBe(1);
    expect(deps.pushSender.sent[0]!.data.requestedByName).toBe(EMPTY_DISPLAY_NAME_FALLBACK);
    expect(deps.pushSender.sent[0]!.data.requestedByName).not.toBe("ghost-uid");
  });

  it("logs a class-of-event warning (never the uid) when the requester is missing from the family roster (B32)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);

    await createLocateRequest(baseInput({ uid: "ghost-uid" }), deps);

    expect(warnSpy).toHaveBeenCalledOnce();
    const loggedMessage = warnSpy.mock.calls[0]!.join(" ");
    expect(loggedMessage).toContain("createLocateRequest");
    expect(loggedMessage).toContain("missing from family roster");
    expect(loggedMessage).not.toContain("ghost-uid");
    warnSpy.mockRestore();
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

  it("passes the server-composed title through PushMessage.notificationTitle (specs/001 §8.1 amended 2026-09-06, 000 §O8) — exact string pinned", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    await createLocateRequest(baseInput(), deps);

    expect(deps.pushSender.sent.length).toBe(1);
    expectNotificationTitle(deps.pushSender.sent[0]!, "LOCATE_REQUEST", "Eric is locating you");
  });

  it("composes the notificationTitle from the resolved requestedByName using the §1.4 placeholder, never the raw uid, when the requester falls back", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    await createLocateRequest(baseInput({ uid: "ghost-uid" }), deps);

    expectNotificationTitle(deps.pushSender.sent[0]!, "LOCATE_REQUEST", `${EMPTY_DISPLAY_NAME_FALLBACK} is locating you`);
  });

  it("re-normalizes a hostile pre-existing stored displayName when composing the LOCATE_REQUEST title (specs/001 §1.4, B29 review finding 5)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: REQUESTER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    // Hostile value stored directly (bypassing the schema-level normalizer entirely) — this
    // simulates a displayName written BEFORE B29's write-time normalizer shipped, which the
    // write-time fix alone cannot clean since it is not retroactive.
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: REQUESTER_UID,
      role: "parent",
      displayName: "Eric\u202Etsohg",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: TARGET_UID,
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    await createLocateRequest(baseInput(), deps);

    expectNotificationTitle(deps.pushSender.sent[0]!, "LOCATE_REQUEST", "Erictsohg is locating you");
  });

  it("substitutes \"Someone\" when the stored requester displayName is ENTIRELY forbidden characters (specs/001 \u00a71.4)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: REQUESTER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    // Entirely forbidden characters (bidi override + isolate) -- normalizeDisplayText
    // reduces this to the empty string, unlike the partially-hostile "Eric\u202Etsohg"
    // case above, which still has real name characters left over after stripping.
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: REQUESTER_UID,
      role: "parent",
      displayName: "\u202E\u2066",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: TARGET_UID,
      role: "member",
      displayName: "Noor",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));

    await createLocateRequest(baseInput(), deps);

    // No leading space, no missing name: "Someone is locating you", NOT " is locating you".
    expectNotificationTitle(deps.pushSender.sent[0]!, "LOCATE_REQUEST", "Someone is locating you");
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

  it("a non-throwing 'error' outcome (e.g. FCM 5xx) creates the request as pushFailed without marking the device pushInvalid (specs/001 §6.1/§6.2 amended 2026-09-06)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a", pushInvalid: false }));
    deps.pushSender.setOutcome("error");

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.status).toBe("pushFailed");
    const stored = await deps.deviceRepo.getDevice(TARGET_UID, DEVICE_A);
    expect(stored?.pushInvalid).toBe(false); // the token is not known bad, only the send attempt failed
  });

  it("a thrown transport failure (OAuth exchange, FCM 5xx, network error) creates the request as pushFailed instead of propagating (specs/001 §6.1 amended 2026-09-06)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));
    deps.pushSender.setThrows(new Error("FCM OAuth2 token exchange failed: HTTP 503"));

    const result = await createLocateRequest(baseInput(), deps);

    expect(result.created).toBe(true);
    expect(result.status).toBe("pushFailed");
    expect(result.lastKnown).toBeNull(); // requester still gets an answer (last-known), not a 500
  });

  it("a thrown transport failure does NOT mark the device pushInvalid (the token is not known bad)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a", pushInvalid: false }));
    deps.pushSender.setThrows(new Error("network error"));

    await createLocateRequest(baseInput(), deps);

    const stored = await deps.deviceRepo.getDevice(TARGET_UID, DEVICE_A);
    expect(stored?.pushInvalid).toBe(false);
  });

  it("the locate request is still persisted as pushFailed after a thrown transport failure (not just returned)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    deps.deviceRepo.seed(TARGET_UID, device({ pushToken: "fcm-token-a" }));
    deps.pushSender.setThrows(new Error("network error"));

    const result = await createLocateRequest(baseInput(), deps);

    const stored = await deps.locateRequestRepo.get(FAMILY_ID, result.requestId);
    expect(stored?.status).toBe("pushFailed");
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
