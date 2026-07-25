// specs/002 §3.1-§3.3/§6 — BlobHistoryStore against real Azurite append blobs: concurrent
// AppendBlock interleaving, the UTC-midnight day-blob split, and cursor pagination across
// day boundaries + multi-device merge. Requires Azurite (`npm run dev:storage`); run via
// `npm run test:integration`.

import { beforeAll, describe, expect, it } from "vitest";
import { ensureContainers } from "./support/ensureStorage";
import { testDeviceId, testFamilyId, testUserId } from "./support/ids";
import { BlobHistoryStore } from "../../src/adapters/blobs/historyBlobStore";
import type { EventLine, FixLine } from "../../src/ports/historyStore";

function fixLine(overrides: Partial<FixLine> = {}): FixLine {
  return {
    fixId: testDeviceId(),
    recordedAt: "2026-07-19T09:00:00Z",
    receivedAt: "2026-07-19T09:00:02Z",
    lat: 51.0543,
    lon: 3.7174,
    accuracyM: 12.5,
    batteryPct: 78,
    source: "periodic",
    ...overrides,
  };
}

function eventLine(overrides: Partial<EventLine> = {}): EventLine {
  return {
    eventId: testDeviceId(),
    userId: "u2",
    deviceId: "device-1",
    geofenceId: "gf_home",
    geofenceName: "Home",
    lat: 51.0543,
    lon: 3.7174,
    radiusM: 150,
    transition: "enter",
    recordedAt: "2026-07-19T15:00:00Z",
    receivedAt: "2026-07-19T15:00:02Z",
    ...overrides,
  };
}

describe("integration/BlobHistoryStore — history container (specs/002 §3.1-§3.3/§6)", () => {
  beforeAll(async () => {
    await ensureContainers("history", "events");
  }, 30_000);

  it("two concurrent appends to the same day blob both land, and the reader sorts by recordedAt", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const userId = testUserId();
    const deviceId = testDeviceId();

    // Appended out of chronological order, concurrently — AppendBlock is atomic per call
    // so both writes land regardless of arrival order (002 §3.2).
    await Promise.all([
      store.appendFix(familyId, userId, deviceId, fixLine({ fixId: "fix-late", recordedAt: "2026-07-19T09:10:00Z" })),
      store.appendFix(
        familyId,
        userId,
        deviceId,
        fixLine({ fixId: "fix-early", recordedAt: "2026-07-19T09:00:00Z" }),
      ),
    ]);

    const page = await store.readFixHistory(familyId, userId, deviceId, "2026-07-19", "2026-07-19", 500, null);

    expect(page.items.map((i) => i.fixId)).toEqual(["fix-early", "fix-late"]);
    expect(page.nextCursor).toBeNull();
  });

  it("a device's fixes spanning UTC midnight land in two separate day blobs, both readable in one ranged query", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const userId = testUserId();
    const deviceId = testDeviceId();

    await store.appendFix(
      familyId,
      userId,
      deviceId,
      fixLine({ fixId: "fix-before-midnight", recordedAt: "2026-07-19T23:59:00Z" }),
    );
    await store.appendFix(
      familyId,
      userId,
      deviceId,
      fixLine({ fixId: "fix-after-midnight", recordedAt: "2026-07-20T00:01:00Z" }),
    );

    const dayBefore = await store.readFixHistory(familyId, userId, deviceId, "2026-07-19", "2026-07-19", 500, null);
    expect(dayBefore.items.map((i) => i.fixId)).toEqual(["fix-before-midnight"]);

    const dayAfter = await store.readFixHistory(familyId, userId, deviceId, "2026-07-20", "2026-07-20", 500, null);
    expect(dayAfter.items.map((i) => i.fixId)).toEqual(["fix-after-midnight"]);

    const spanning = await store.readFixHistory(familyId, userId, deviceId, "2026-07-19", "2026-07-20", 500, null);
    expect(spanning.items.map((i) => i.fixId)).toEqual(["fix-before-midnight", "fix-after-midnight"]);
  });

  it("dedupes a duplicate fixId within a day, keeping the latest receivedAt (crash-retry edge, 002 §3.3)", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const userId = testUserId();
    const deviceId = testDeviceId();

    await store.appendFix(
      familyId,
      userId,
      deviceId,
      fixLine({ fixId: "fix-1", recordedAt: "2026-07-19T09:00:00Z", receivedAt: "2026-07-19T09:00:02Z", lat: 1 }),
    );
    // Same fixId re-appended (e.g. a retried write after a crash) with a later receivedAt.
    await store.appendFix(
      familyId,
      userId,
      deviceId,
      fixLine({ fixId: "fix-1", recordedAt: "2026-07-19T09:00:00Z", receivedAt: "2026-07-19T09:05:00Z", lat: 2 }),
    );

    const page = await store.readFixHistory(familyId, userId, deviceId, "2026-07-19", "2026-07-19", 500, null);

    expect(page.items).toHaveLength(1);
    expect(page.items[0]?.lat).toBe(2); // the later receivedAt write wins
  });

  it("merges multiple devices for a user when deviceId is omitted", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const userId = testUserId();
    const deviceA = testDeviceId();
    const deviceB = testDeviceId();

    await store.appendFix(familyId, userId, deviceA, fixLine({ fixId: "a1", recordedAt: "2026-07-19T09:00:00Z" }));
    await store.appendFix(familyId, userId, deviceB, fixLine({ fixId: "b1", recordedAt: "2026-07-19T09:05:00Z" }));
    await store.appendFix(familyId, userId, deviceA, fixLine({ fixId: "a2", recordedAt: "2026-07-19T09:10:00Z" }));

    const page = await store.readFixHistory(familyId, userId, undefined, "2026-07-19", "2026-07-19", 500, null);

    expect(page.items.map((i) => ({ fixId: i.fixId, deviceId: i.deviceId }))).toEqual([
      { fixId: "a1", deviceId: deviceA },
      { fixId: "b1", deviceId: deviceB },
      { fixId: "a2", deviceId: deviceA },
    ]);
  });

  it("cursor round-trip across a day boundary with multi-device merge: pages never duplicate or skip", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const userId = testUserId();
    const deviceA = testDeviceId();
    const deviceB = testDeviceId();

    // Day 1: two devices interleaved. Day 2: one more fix.
    await store.appendFix(familyId, userId, deviceA, fixLine({ fixId: "d1-a1", recordedAt: "2026-07-19T09:00:00Z" }));
    await store.appendFix(familyId, userId, deviceB, fixLine({ fixId: "d1-b1", recordedAt: "2026-07-19T09:02:00Z" }));
    await store.appendFix(familyId, userId, deviceA, fixLine({ fixId: "d1-a2", recordedAt: "2026-07-19T09:04:00Z" }));
    await store.appendFix(familyId, userId, deviceB, fixLine({ fixId: "d2-b1", recordedAt: "2026-07-20T09:00:00Z" }));

    const collected: string[] = [];
    let cursor: string | null = null;
    let guard = 0;
    do {
      const page = await store.readFixHistory(familyId, userId, undefined, "2026-07-19", "2026-07-20", 2, cursor);
      collected.push(...page.items.map((i) => i.fixId));
      cursor = page.nextCursor;
      guard += 1;
    } while (cursor !== null && guard < 10);

    expect(collected).toEqual(["d1-a1", "d1-b1", "d1-a2", "d2-b1"]);
  });

  it("events: two concurrent appends to the same family/day land, and the reader sorts + filters by userId", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();

    await Promise.all([
      store.appendEvent(familyId, eventLine({ eventId: "e-late", userId: "u2", recordedAt: "2026-07-19T15:10:00Z" })),
      store.appendEvent(familyId, eventLine({ eventId: "e-early", userId: "u3", recordedAt: "2026-07-19T15:00:00Z" })),
    ]);

    const all = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", undefined, 500, null);
    expect(all.items.map((e) => e.eventId)).toEqual(["e-early", "e-late"]);

    const filtered = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", "u2", 500, null);
    expect(filtered.items.map((e) => e.eventId)).toEqual(["e-late"]);
  });

  it("events: preserves null geofenceName/lat/lon/radiusM for an unknown geofenceId at write time", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();

    await store.appendEvent(
      familyId,
      eventLine({
        eventId: "e-unknown-gf",
        geofenceId: "gf_deleted",
        geofenceName: null,
        lat: null,
        lon: null,
        radiusM: null,
      }),
    );

    const page = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", undefined, 500, null);

    expect(page.items[0]).toMatchObject({ geofenceName: null, lat: null, lon: null, radiusM: null });
  });

  it("deleteUserPrefix wipes only that user's history/{familyId}/{userId}/ prefix, leaving another user's history intact (specs/002 §4.2 step 6, B18)", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const subjectUserId = testUserId();
    const otherUserId = testUserId();
    const deviceId = testDeviceId();

    await store.appendFix(familyId, subjectUserId, deviceId, fixLine({ fixId: "subject-fix" }));
    await store.appendFix(familyId, otherUserId, deviceId, fixLine({ fixId: "other-fix" }));

    await store.deleteUserPrefix(familyId, subjectUserId);

    const subjectPage = await store.readFixHistory(familyId, subjectUserId, undefined, "2026-07-19", "2026-07-19", 500, null);
    expect(subjectPage.items).toEqual([]);
    const otherPage = await store.readFixHistory(familyId, otherUserId, undefined, "2026-07-19", "2026-07-19", 500, null);
    expect(otherPage.items.map((i) => i.fixId)).toEqual(["other-fix"]);
  });

  it("deleteUserPrefix is idempotent (a second call on an already-empty prefix is a no-op)", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const subjectUserId = testUserId();

    await expect(store.deleteUserPrefix(familyId, subjectUserId)).resolves.toBeUndefined();
    await expect(store.deleteUserPrefix(familyId, subjectUserId)).resolves.toBeUndefined();
  });

  it("eraseUserFromEvents (008 §4.3, 002 §4.2): removes only the subject's lines from a day blob, leaving every other member's line untouched", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const subjectUserId = testUserId();
    const otherUserId = testUserId();

    await store.appendEvent(familyId, eventLine({ eventId: "e-subject-1", userId: subjectUserId, recordedAt: "2026-07-19T15:00:00Z" }));
    await store.appendEvent(familyId, eventLine({ eventId: "e-other-1", userId: otherUserId, recordedAt: "2026-07-19T15:01:00Z" }));
    await store.appendEvent(familyId, eventLine({ eventId: "e-subject-2", userId: subjectUserId, recordedAt: "2026-07-19T15:02:00Z" }));
    await store.appendEvent(familyId, eventLine({ eventId: "e-other-2", userId: otherUserId, recordedAt: "2026-07-19T15:03:00Z" }));

    await store.eraseUserFromEvents(familyId, subjectUserId);

    const all = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", undefined, 500, null);
    expect(all.items.map((e) => e.eventId).sort()).toEqual(["e-other-1", "e-other-2"]);
  });

  it("eraseUserFromEvents is a no-op when the subject has no lines in a day blob (other lines byte-identical)", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const subjectUserId = testUserId();
    const otherUserId = testUserId();

    await store.appendEvent(familyId, eventLine({ eventId: "e-other-only", userId: otherUserId, recordedAt: "2026-07-19T15:00:00Z" }));

    await store.eraseUserFromEvents(familyId, subjectUserId);

    const all = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", undefined, 500, null);
    expect(all.items.map((e) => e.eventId)).toEqual(["e-other-only"]);
  });

  it("eraseUserFromEvents is idempotent (calling it again after the subject's lines are already gone is a no-op)", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const subjectUserId = testUserId();
    const otherUserId = testUserId();

    await store.appendEvent(familyId, eventLine({ eventId: "e-subject", userId: subjectUserId, recordedAt: "2026-07-19T15:00:00Z" }));
    await store.appendEvent(familyId, eventLine({ eventId: "e-other", userId: otherUserId, recordedAt: "2026-07-19T15:01:00Z" }));

    await store.eraseUserFromEvents(familyId, subjectUserId);
    await store.eraseUserFromEvents(familyId, subjectUserId);

    const all = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", undefined, 500, null);
    expect(all.items.map((e) => e.eventId)).toEqual(["e-other"]);
  });

  it("eraseUserFromEvents survives a genuinely concurrent §3.2 append to the same day blob — no other member's line is ever lost (008 §4.3, 002 §4.2/§6)", async () => {
    const store = new BlobHistoryStore();
    const familyId = testFamilyId();
    const subjectUserId = testUserId();
    const otherUserId = testUserId();

    // Pre-existing lines: one of the subject's (to be erased), one of another member's
    // (must survive).
    await store.appendEvent(familyId, eventLine({ eventId: "e-subject-pre", userId: subjectUserId, recordedAt: "2026-07-19T15:00:00Z" }));
    await store.appendEvent(familyId, eventLine({ eventId: "e-other-pre", userId: otherUserId, recordedAt: "2026-07-19T15:01:00Z" }));

    // Fire the erasure concurrently with a fresh append from another member — a genuine
    // network race with no artificial synchronization, same idiom as the "two concurrent
    // appends" test above. The concurrent append's line must survive the rewrite regardless
    // of interleaving (the delete+recreate race unions it back in, 002 §4.2).
    await Promise.all([
      store.eraseUserFromEvents(familyId, subjectUserId),
      store.appendEvent(familyId, eventLine({ eventId: "e-other-concurrent", userId: otherUserId, recordedAt: "2026-07-19T15:02:00Z" })),
    ]);

    const all = await store.readEventHistory(familyId, "2026-07-19", "2026-07-19", undefined, 500, null);
    const eventIds = all.items.map((e) => e.eventId).sort();
    expect(eventIds).not.toContain("e-subject-pre");
    expect(eventIds).toContain("e-other-pre");
    expect(eventIds).toContain("e-other-concurrent");
    // Every surviving line still belongs to otherUserId — none of the subject's leaked back in.
    expect(all.items.every((e) => e.userId === otherUserId)).toBe(true);
  });
});
