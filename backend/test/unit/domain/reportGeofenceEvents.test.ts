import { describe, expect, it, vi } from "vitest";
import { reportGeofenceEvents } from "../../../src/domain/geofence/reportGeofenceEvents";
import { getFeatures } from "../../../src/domain/plan";
import { EMPTY_DISPLAY_NAME_FALLBACK } from "../../../src/domain/text/normalizeDisplayText";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import { InMemoryFamilyRepo } from "../../fakes/inMemoryFamilyRepo";
import { InMemoryGeofenceConfigRepo } from "../../fakes/inMemoryGeofenceConfigRepo";
import { InMemoryIdempotencyRepo } from "../../fakes/inMemoryIdempotencyRepo";
import { InMemoryHistoryStore } from "../../fakes/inMemoryHistoryStore";
import { InMemoryUsageRepo } from "../../fakes/inMemoryUsageRepo";
import { InMemoryEntitlementsRepo } from "../../fakes/inMemoryEntitlementsRepo";
import { FakePushSender } from "../../fakes/fakePushSender";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import { expectNotificationTitle } from "../../support/expectPushMessage";
import type { DeviceRecord } from "../../../src/ports/repositories";

const FAMILY_ID = "fam_9J2Kq7Lm3NpR5sTvWxYz";
const REPORTER_UID = "u1";
const OTHER_UID = "u2";
const DEVICE_ID = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const OTHER_DEVICE_ID = "4f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2c";
const NOW = "2026-07-19T15:03:22Z";

const HOME_GEOFENCE = {
  geofenceId: "gf_home",
  name: "Home",
  lat: 51.0543,
  lon: 3.7174,
  radiusM: 150,
  icon: "home",
  notifyOnEnter: true,
  notifyOnExit: true,
};

function buildDeps() {
  const entitlementsRepo = new InMemoryEntitlementsRepo();
  entitlementsRepo.seed(FAMILY_ID, { subscriptionStatus: "free", updatedAt: "2026-07-01T00:00:00Z" });
  return {
    deviceRepo: new InMemoryDeviceRepo(),
    familyRepo: new InMemoryFamilyRepo(),
    geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
    idempotencyRepo: new InMemoryIdempotencyRepo(),
    historyStore: new InMemoryHistoryStore(),
    usageRepo: new InMemoryUsageRepo(),
    entitlementsRepo,
    pushSender: new FakePushSender(),
    clock: new FixedClock(new Date(NOW)),
  };
}

async function seedFamily(deps: ReturnType<typeof buildDeps>): Promise<void> {
  await deps.familyRepo.createFamily({
    familyId: FAMILY_ID,
    familyName: "Wauters",
    createdBy: REPORTER_UID,
    createdAt: "2026-07-01T00:00:00Z",
  });
  // OTHER_UID is added FIRST deliberately: a `.find(u => true)`-style mutant (always
  // matching the first roster entry regardless of userId) would then resolve the WRONG
  // displayName ("Eric" instead of the reporter's actual "Noor").
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: OTHER_UID,
    role: "parent",
    displayName: "Eric",
    joinedAt: "2026-07-01T00:00:00Z",
  });
  await deps.familyRepo.addMember(FAMILY_ID, {
    userId: REPORTER_UID,
    role: "member",
    displayName: "Noor",
    joinedAt: "2026-07-01T00:00:00Z",
  });
}

function seedReporterDevice(deps: ReturnType<typeof buildDeps>, overrides: Partial<DeviceRecord> = {}): void {
  deps.deviceRepo.seed(REPORTER_UID, {
    deviceId: DEVICE_ID,
    ownerUserId: REPORTER_UID,
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Noor's phone",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  });
}

function seedOtherDevice(deps: ReturnType<typeof buildDeps>, overrides: Partial<DeviceRecord> = {}): void {
  deps.deviceRepo.seed(OTHER_UID, {
    deviceId: OTHER_DEVICE_ID,
    ownerUserId: OTHER_UID,
    platform: "ios",
    model: "iPhone 15",
    appVersion: "1.0.0",
    deviceName: "Eric's phone",
    pushToken: "fcm-token-other",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-01T00:00:00Z",
    ...overrides,
  });
}

function event(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    eventId: "a1e2b3c4-0000-4000-8000-000000000001",
    geofenceId: "gf_home",
    transition: "enter",
    recordedAt: "2026-07-19T15:03:22Z",
    ...overrides,
  };
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    uid: REPORTER_UID,
    familyId: FAMILY_ID as string | null,
    deviceId: DEVICE_ID as string | null,
    body: { events: [event()] },
    ...overrides,
  };
}

describe("domain/geofence/reportGeofenceEvents", () => {
  it("throws FAMILY_NOT_FOUND when the caller has no family", async () => {
    const deps = buildDeps();
    await expectAppError(reportGeofenceEvents(baseInput({ familyId: null }), deps), "FAMILY_NOT_FOUND");
  });

  it("throws INTERNAL_ERROR when the family has no Entitlements record", async () => {
    const deps = {
      deviceRepo: new InMemoryDeviceRepo(),
      familyRepo: new InMemoryFamilyRepo(),
      geofenceConfigRepo: new InMemoryGeofenceConfigRepo(),
      idempotencyRepo: new InMemoryIdempotencyRepo(),
      historyStore: new InMemoryHistoryStore(),
      usageRepo: new InMemoryUsageRepo(),
      entitlementsRepo: new InMemoryEntitlementsRepo(), // deliberately not seeded
      pushSender: new FakePushSender(),
      clock: new FixedClock(new Date(NOW)),
    };
    await expectAppError(reportGeofenceEvents(baseInput(), deps), "INTERNAL_ERROR");
  });

  it("throws DEVICE_NOT_FOUND when X-Device-Id header is missing", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    await expect(reportGeofenceEvents(baseInput({ deviceId: null }), deps)).rejects.toMatchObject({
      code: "DEVICE_NOT_FOUND",
      message: "X-Device-Id header is required",
    });
  });

  it("throws DEVICE_NOT_FOUND when the device does not exist", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    await expectAppError(reportGeofenceEvents(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("throws DEVICE_NOT_FOUND when the device is registered to a different user (§1.2 ownership)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps, { ownerUserId: "someone-else" });
    await expectAppError(reportGeofenceEvents(baseInput(), deps), "DEVICE_NOT_FOUND");
  });

  it("throws TRACKING_PAUSED with details.deviceSettings when the device is paused", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps, { trackingEnabled: false, syncIntervalMinutes: 30 });
    await expectAppError(reportGeofenceEvents(baseInput(), deps), "TRACKING_PAUSED", {
      deviceSettings: { syncIntervalMinutes: 30, trackingEnabled: false },
    });
  });

  it("throws VALIDATION_FAILED for an empty events batch", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    await expectAppError(reportGeofenceEvents(baseInput({ body: { events: [] } }), deps), "VALIDATION_FAILED");
  });

  it("throws VALIDATION_FAILED for a batch of 21 events", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    const events = Array.from({ length: 21 }, (_, i) =>
      event({ eventId: `a1e2b3c4-0000-4000-8000-${String(i).padStart(12, "0")}` }),
    );
    await expectAppError(reportGeofenceEvents(baseInput({ body: { events } }), deps), "VALIDATION_FAILED");
  });

  it("accepts exactly 20 events (boundary: only STRICTLY more than 20 fails)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    const events = Array.from({ length: 20 }, (_, i) =>
      event({ eventId: `a1e2b3c4-0000-4000-8000-${String(i).padStart(12, "0")}` }),
    );
    const result = await reportGeofenceEvents(baseInput({ body: { events } }), deps);
    expect(result.accepted).toBe(20);
  });

  it("accepts an unknown geofenceId: stored with all frozen fields null, no fan-out", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    // No config seeded at all -> gf_home is "unknown" to this family.

    const result = await reportGeofenceEvents(baseInput(), deps);

    expect(result.accepted).toBe(1);
    expect(deps.historyStore.events).toHaveLength(1);
    const stored = deps.historyStore.events[0]!.event;
    expect(stored.geofenceName).toBeNull();
    expect(stored.lat).toBeNull();
    expect(stored.lon).toBeNull();
    expect(stored.radiusM).toBeNull();
    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("freezes geofenceName/lat/lon/radiusM from the current config when the geofenceId is known", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput(), deps);

    const stored = deps.historyStore.events[0]!.event;
    expect(stored.geofenceName).toBe("Home");
    expect(stored.lat).toBe(51.0543);
    expect(stored.lon).toBe(3.7174);
    expect(stored.radiusM).toBe(150);
  });

  it("always appends history regardless of notify flags", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    deps.geofenceConfigRepo.seedConfig(
      FAMILY_ID,
      { version: 1, geofences: [{ ...HOME_GEOFENCE, notifyOnEnter: false, notifyOnExit: false }] },
      '"cfg-etag"',
    );

    await reportGeofenceEvents(baseInput(), deps);

    expect(deps.historyStore.events).toHaveLength(1);
  });

  it("sends GEOFENCE_EVENT to all family devices except the reporter when notifyOnEnter is true", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps, { pushToken: "fcm-token-reporter" });
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput({ body: { events: [event({ transition: "enter" })] } }), deps);

    expect(deps.pushSender.sent).toHaveLength(1);
    const message = deps.pushSender.sent[0]!;
    expect(message.token).toBe("fcm-token-other");
    expectNotificationTitle(message, "GEOFENCE_EVENT", "Noor arrived at Home");
    expect(message.data).toEqual({
      type: "GEOFENCE_EVENT",
      userId: REPORTER_UID,
      displayName: "Noor",
      geofenceId: "gf_home",
      geofenceName: "Home",
      transition: "enter",
      recordedAt: "2026-07-19T15:03:22Z",
    });

    // A successful ("ok") send must NOT mark the target device pushInvalid.
    expect((await deps.deviceRepo.getDevice(OTHER_UID, OTHER_DEVICE_ID))?.pushInvalid).toBe(false);
  });

  it("re-normalizes a hostile pre-existing stored displayName AND geofenceName when composing the GEOFENCE_EVENT title (specs/001 §1.4, B29 review finding 5)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: REPORTER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: OTHER_UID,
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Hostile value stored directly (bypassing the schema-level normalizer entirely) — this
    // simulates a displayName written BEFORE B29's write-time normalizer shipped, which the
    // write-time fix alone cannot clean since it is not retroactive.
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: REPORTER_UID,
      role: "member",
      displayName: "Noor\u202Etsohg",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    seedReporterDevice(deps, { pushToken: "fcm-token-reporter" });
    seedOtherDevice(deps);
    // Same for geofenceName — a config document written before B29's schema-level bound.
    const hostileGeofence = { ...HOME_GEOFENCE, name: "Ho\u202Eme" };
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [hostileGeofence] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput({ body: { events: [event({ transition: "enter" })] } }), deps);

    expect(deps.pushSender.sent).toHaveLength(1);
    expectNotificationTitle(deps.pushSender.sent[0]!, "GEOFENCE_EVENT", "Noortsohg arrived at Home");
  });

  it("re-normalizes a hostile pre-existing stored displayName AND geofenceName in the data map, not only in the title (specs/001 \u00a71.4, B34)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: REPORTER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: OTHER_UID,
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Hostile-but-non-empty: survives normalization as something, so it is NOT caught by
    // B32's empty-string/uid-fallback substitution \u2014 it must be caught by re-normalizing
    // the value itself before writing it into the data map, same as the title beside it.
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: REPORTER_UID,
      role: "member",
      displayName: "Noor\u202Etsohg",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    seedReporterDevice(deps, { pushToken: "fcm-token-reporter" });
    seedOtherDevice(deps);
    const hostileGeofence = { ...HOME_GEOFENCE, name: "Ho\u202Eme" };
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [hostileGeofence] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput({ body: { events: [event({ transition: "enter" })] } }), deps);

    expect(deps.pushSender.sent).toHaveLength(1);
    const sentData = deps.pushSender.sent[0]!.data;
    expect(sentData.displayName).toBe("Noortsohg");
    expect(sentData.displayName).not.toBe("Noor\u202Etsohg");
    expect(sentData.geofenceName).toBe("Home");
    expect(sentData.geofenceName).not.toBe("Ho\u202Eme");
  });

  it("substitutes \"Someone\" when the stored displayName is ENTIRELY forbidden characters (specs/001 \u00a71.4)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: REPORTER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: OTHER_UID,
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Entirely forbidden characters (bidi override + isolate) -- normalizeDisplayText
    // reduces this to the empty string, unlike the partially-hostile "Noor\u202Etsohg"
    // case above, which still has real name characters left over after stripping.
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: REPORTER_UID,
      role: "member",
      displayName: "\u202E\u2066",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    seedReporterDevice(deps, { pushToken: "fcm-token-reporter" });
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput({ body: { events: [event({ transition: "enter" })] } }), deps);

    expect(deps.pushSender.sent).toHaveLength(1);
    // No leading space, no missing name: "Someone arrived at Home", NOT " arrived at Home".
    expectNotificationTitle(deps.pushSender.sent[0]!, "GEOFENCE_EVENT", "Someone arrived at Home");
  });

  it("substitutes \"a place\" when the stored geofenceName is ENTIRELY forbidden characters, independently of displayName (specs/001 \u00a71.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps, { pushToken: "fcm-token-reporter" });
    seedOtherDevice(deps);
    // Entirely forbidden characters -- a geofence config document written before B29's
    // schema-level bound, where nothing but hostile characters ever made it into `name`.
    const hostileGeofence = { ...HOME_GEOFENCE, name: "\u202E\u2066" };
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [hostileGeofence] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput({ body: { events: [event({ transition: "enter" })] } }), deps);

    expect(deps.pushSender.sent).toHaveLength(1);
    // displayName ("Noor") normalizes fine here -- only geofenceName is empty -- proving the
    // two fallbacks are substituted independently, not as an all-or-nothing pair.
    expectNotificationTitle(deps.pushSender.sent[0]!, "GEOFENCE_EVENT", "Noor arrived at a place");
  });

  it("falls back to the §1.4 placeholder (never the uid) as displayName when they're not in the family roster", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: OTHER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: OTHER_UID,
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Deliberately NOT adding REPORTER_UID as a family member (edge case: a stale device
    // registration outliving its owner's membership) — resolveDisplayName must fall back
    // to the §1.4 placeholder rather than the uid (specs/001 §1.4: "A user id MUST NOT be
    // used as the fallback: it is opaque to the reader and would expose an internal
    // identifier to every other family member") or crashing on a missing roster entry.
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput(), deps);

    expect(deps.pushSender.sent[0]!.data.displayName).toBe(EMPTY_DISPLAY_NAME_FALLBACK);
    expect(deps.pushSender.sent[0]!.data.displayName).not.toBe(REPORTER_UID);
  });

  it("logs a class-of-event warning (never the uid) when the reporter is missing from the family roster (B32)", async () => {
    const deps = buildDeps();
    await deps.familyRepo.createFamily({
      familyId: FAMILY_ID,
      familyName: "Wauters",
      createdBy: OTHER_UID,
      createdAt: "2026-07-01T00:00:00Z",
    });
    await deps.familyRepo.addMember(FAMILY_ID, {
      userId: OTHER_UID,
      role: "parent",
      displayName: "Eric",
      joinedAt: "2026-07-01T00:00:00Z",
    });
    // Deliberately NOT adding REPORTER_UID (see the test above).
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);

    await reportGeofenceEvents(baseInput(), deps);

    expect(warnSpy).toHaveBeenCalledOnce();
    const loggedMessage = warnSpy.mock.calls[0]!.join(" ");
    expect(loggedMessage).toContain("reportGeofenceEvents");
    expect(loggedMessage).toContain("missing from family roster");
    expect(loggedMessage).not.toContain(REPORTER_UID);
    expect(loggedMessage).not.toContain(DEVICE_ID);
    warnSpy.mockRestore();
  });

  it("resolves the reporter's displayName and the family device roster only ONCE per batch (caching), fanning out one listDevices call per family member (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    let listMembersCalls = 0;
    const originalListMembers = deps.familyRepo.listMembers.bind(deps.familyRepo);
    deps.familyRepo.listMembers = async (familyId: string) => {
      listMembersCalls++;
      return originalListMembers(familyId);
    };
    let listDevicesCalls = 0;
    const originalListDevices = deps.deviceRepo.listDevices.bind(deps.deviceRepo);
    deps.deviceRepo.listDevices = async (ownerUserId: string) => {
      listDevicesCalls++;
      return originalListDevices(ownerUserId);
    };

    // Two DIFFERENT events, both triggering fan-out (enter matches notifyOnEnter, exit
    // matches notifyOnExit) — displayName/family-roster resolution must happen once, not
    // once per fanned-out event. listDevices is called once PER MEMBER (2 members here),
    // never once per event.
    await reportGeofenceEvents(
      baseInput({
        body: {
          events: [
            event({ eventId: "a1e2b3c4-0000-4000-8000-000000000010", transition: "enter" }),
            event({ eventId: "a1e2b3c4-0000-4000-8000-000000000011", transition: "exit" }),
          ],
        },
      }),
      deps,
    );

    expect(listMembersCalls).toBe(1);
    expect(listDevicesCalls).toBe(2);
    expect(deps.pushSender.sent).toHaveLength(2);
  });

  it("uses the 'left' title for an exit transition", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(
      baseInput({
        body: {
          events: [
            event({
              eventId: "a1e2b3c4-0000-4000-8000-000000000002",
              transition: "exit",
            }),
          ],
        },
      }),
      deps,
    );

    expectNotificationTitle(deps.pushSender.sent[0]!, "GEOFENCE_EVENT", "Noor left Home");
  });

  it("does NOT fan out when notifyOnEnter is false for an enter transition", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(
      FAMILY_ID,
      { version: 1, geofences: [{ ...HOME_GEOFENCE, notifyOnEnter: false }] },
      '"cfg-etag"',
    );

    await reportGeofenceEvents(baseInput({ body: { events: [event({ transition: "enter" })] } }), deps);

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("does NOT fan out when notifyOnExit is false for an exit transition", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(
      FAMILY_ID,
      { version: 1, geofences: [{ ...HOME_GEOFENCE, notifyOnExit: false }] },
      '"cfg-etag"',
    );

    await reportGeofenceEvents(
      baseInput({
        body: { events: [event({ eventId: "a1e2b3c4-0000-4000-8000-000000000003", transition: "exit" })] },
      }),
      deps,
    );

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("never sends a push to the reporting device itself, even with a valid token", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps, { pushToken: "fcm-token-reporter" });
    // no other devices at all
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput(), deps);

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("never fans out to a stranger's device (not a member of this family) — fan-out only visits the family's roster partitions (002 §2.4)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    deps.deviceRepo.seed("stranger", {
      deviceId: "5f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2e",
      ownerUserId: "stranger",
      platform: "ios",
      model: "Stranger's phone",
      appVersion: "1.0.0",
      deviceName: "Stranger's phone",
      pushToken: "fcm-token-stranger",
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput(), deps);

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("skips fan-out to devices with no pushToken or pushInvalid: true", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps, { pushToken: undefined });
    deps.deviceRepo.seed(OTHER_UID, {
      deviceId: "5f1a3b0d-7c2e-5f9a-ab3c-8d6e5f4a3b2d",
      ownerUserId: OTHER_UID,
      platform: "ios",
      model: "iPhone 14",
      appVersion: "1.0.0",
      deviceName: "Eric's tablet",
      pushToken: "fcm-token-invalid",
      pushInvalid: true,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: "2026-07-01T00:00:00Z",
      lastSeenAt: "2026-07-01T00:00:00Z",
    });
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    await reportGeofenceEvents(baseInput(), deps);

    expect(deps.pushSender.sent).toHaveLength(0);
  });

  it("marks a target device pushInvalid: true when FCM reports an invalid token", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');
    deps.pushSender.setOutcome("invalidToken");

    await reportGeofenceEvents(baseInput(), deps);

    const stored = await deps.deviceRepo.getDevice(OTHER_UID, OTHER_DEVICE_ID);
    expect(stored?.pushInvalid).toBe(true);
  });

  it("does not fail the request when a fan-out push throws (best-effort)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');
    deps.pushSender.send = async () => {
      throw new Error("transport failure");
    };

    const result = await reportGeofenceEvents(baseInput(), deps);

    expect(result.accepted).toBe(1);
  });

  it("idempotency: replaying the same (deviceId, eventId) counts as a duplicate, no second history/push", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    seedOtherDevice(deps);
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [HOME_GEOFENCE] }, '"cfg-etag"');

    const first = await reportGeofenceEvents(baseInput(), deps);
    expect(first.accepted).toBe(1);
    expect(first.duplicates).toBe(0);

    const replay = await reportGeofenceEvents(baseInput(), deps);
    expect(replay.accepted).toBe(0);
    expect(replay.duplicates).toBe(1);

    expect(deps.historyStore.events).toHaveLength(1);
    expect(deps.pushSender.sent).toHaveLength(1);
  });

  it("piggybacks deviceSettings and the current geofenceEtag in the response (same shape as §5.1)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps, { syncIntervalMinutes: 30 });
    deps.geofenceConfigRepo.seedConfig(FAMILY_ID, { version: 1, geofences: [] }, '"cfg-etag"');

    const result = await reportGeofenceEvents(baseInput(), deps);

    expect(result.deviceSettings).toEqual({ syncIntervalMinutes: 30, trackingEnabled: true });
    expect(result.geofenceEtag).toBe('"cfg-etag"');
    expect(result.features).toEqual(getFeatures("free"));
  });

  it("increments geofenceEvents usage by the accepted count", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);
    const events = [
      event({ eventId: "a1e2b3c4-0000-4000-8000-000000000001" }),
      event({ eventId: "a1e2b3c4-0000-4000-8000-000000000002", recordedAt: "2026-07-19T15:04:00Z" }),
    ];

    await reportGeofenceEvents(baseInput({ body: { events } }), deps);

    expect(await deps.usageRepo.get(FAMILY_ID, "geofenceEvents", "2026-07-19")).toBe(2);
  });

  it("does not increment geofenceEvents usage when the whole batch is duplicates", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);

    await reportGeofenceEvents(baseInput(), deps);
    await reportGeofenceEvents(baseInput(), deps);

    expect(await deps.usageRepo.get(FAMILY_ID, "geofenceEvents", "2026-07-19")).toBe(1);
  });

  it("never even calls usageRepo.increment(\"geofenceEvents\") for an all-duplicate replay (not just a net-zero increment-by-0)", async () => {
    const deps = buildDeps();
    await seedFamily(deps);
    seedReporterDevice(deps);

    await reportGeofenceEvents(baseInput(), deps); // first call: accepted 1

    let geofenceEventsCalls = 0;
    const originalIncrement = deps.usageRepo.increment.bind(deps.usageRepo);
    deps.usageRepo.increment = async (familyId, metric, date, by) => {
      if (metric === "geofenceEvents") geofenceEventsCalls++;
      return originalIncrement(familyId, metric, date, by);
    };

    await reportGeofenceEvents(baseInput(), deps); // fully duplicate replay: accepted 0

    expect(geofenceEventsCalls).toBe(0);
  });

  describe("lastSeenAt refresh (specs/001 §4.2 amended 2026-09-06, 002 §2.4 write-skip)", () => {
    it("refreshes the reporting device's lastSeenAt when it is stale (well over a minute old)", async () => {
      const deps = buildDeps();
      await seedFamily(deps);
      seedReporterDevice(deps, { lastSeenAt: "2026-07-01T00:00:00Z" });

      await reportGeofenceEvents(baseInput(), deps);

      const stored = await deps.deviceRepo.getDevice(REPORTER_UID, DEVICE_ID);
      expect(stored?.lastSeenAt).toBe(new Date(NOW).toISOString());
    });

    it("skips the lastSeenAt write when the device was seen less than a minute ago (write-skip)", async () => {
      const deps = buildDeps();
      await seedFamily(deps);
      const recentlySeen = new Date(new Date(NOW).getTime() - 30_000).toISOString();
      seedReporterDevice(deps, { lastSeenAt: recentlySeen });

      await reportGeofenceEvents(baseInput(), deps);

      const stored = await deps.deviceRepo.getDevice(REPORTER_UID, DEVICE_ID);
      expect(stored?.lastSeenAt).toBe(recentlySeen);
    });

    it("does not clobber a concurrent settings change: trackingEnabled flipped to false after the in-request snapshot still reads false after the refresh (Major review fix, 002 §2.4)", async () => {
      const deps = buildDeps();
      await seedFamily(deps);
      seedReporterDevice(deps, { lastSeenAt: "2026-07-01T00:00:00Z", trackingEnabled: true }); // stale -> triggers a write

      // Simulate a concurrent PATCH /devices/{id} (§4.3) landing between this request's
      // §1.2 ownership snapshot read and its lastSeenAt refresh write.
      const originalGetDevice = deps.deviceRepo.getDevice.bind(deps.deviceRepo);
      deps.deviceRepo.getDevice = async (ownerUserId, deviceId) => {
        const snapshot = await originalGetDevice(ownerUserId, deviceId);
        if (snapshot) {
          await deps.deviceRepo.putDevice(ownerUserId, { ...snapshot, trackingEnabled: false });
        }
        return snapshot;
      };

      await reportGeofenceEvents(baseInput(), deps);

      const stored = await deps.deviceRepo.getDevice(REPORTER_UID, DEVICE_ID);
      expect(stored?.trackingEnabled).toBe(false); // must NOT be reverted to the stale snapshot's true
      expect(stored?.lastSeenAt).toBe(new Date(NOW).toISOString());
    });
  });
});
