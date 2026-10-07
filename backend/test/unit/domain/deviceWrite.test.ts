// 002 §4.3 — a request-path full-row Replace that lost an ETag race must not revert the
// system-written fields (lastNudgedAt, pushInvalid, lastSeenAt) a concurrent writer set.
import { describe, expect, it } from "vitest";
import { reconcileStaleReplace } from "../../../src/domain/device/deviceWrite";
import { InMemoryDeviceRepo } from "../../fakes/inMemoryDeviceRepo";
import type { DeviceRecord } from "../../../src/ports/repositories";

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: "d1",
    ownerUserId: "u1",
    platform: "ios",
    model: "iPhone",
    appVersion: "1.2.0",
    deviceName: "Original",
    pushToken: "tok",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    staleNudgeEnabled: true,
    ...overrides,
  };
}

describe("reconcileStaleReplace (pure)", () => {
  it("keeps the caller's intended fields and adopts the fresh etag", () => {
    const out = reconcileStaleReplace(device({ etag: "e2" }), device({ deviceName: "Renamed", etag: "e1" }));
    expect(out.deviceName).toBe("Renamed");
    expect(out.etag).toBe("e2");
  });
  it("preserves a lastNudgedAt the fresh row has and the snapshot lacks", () => {
    const out = reconcileStaleReplace(device({ lastNudgedAt: "2026-10-07T10:00:00Z" }), device());
    expect(out.lastNudgedAt).toBe("2026-10-07T10:00:00Z");
  });
  it("takes the later lastNudgedAt", () => {
    expect(
      reconcileStaleReplace(device({ lastNudgedAt: "2026-10-07T10:00:00Z" }), device({ lastNudgedAt: "2026-10-06T10:00:00Z" }))
        .lastNudgedAt,
    ).toBe("2026-10-07T10:00:00Z");
    expect(
      reconcileStaleReplace(device({ lastNudgedAt: "2026-10-06T10:00:00Z" }), device({ lastNudgedAt: "2026-10-07T10:00:00Z" }))
        .lastNudgedAt,
    ).toBe("2026-10-07T10:00:00Z");
  });
  it("on an equal instant the fresh row's value is kept", () => {
    expect(
      reconcileStaleReplace(device({ lastSeenAt: "2026-10-07T10:00:00Z" }), device({ lastSeenAt: "2026-10-07T10:00:00.000Z" }))
        .lastSeenAt,
    ).toBe("2026-10-07T10:00:00Z");
  });
  it("leaves lastNudgedAt absent when neither has it", () => {
    expect(reconcileStaleReplace(device(), device())).not.toHaveProperty("lastNudgedAt");
  });
  it("pushInvalid sticks if either side has it", () => {
    expect(reconcileStaleReplace(device({ pushInvalid: true }), device()).pushInvalid).toBe(true);
    expect(reconcileStaleReplace(device(), device({ pushInvalid: true })).pushInvalid).toBe(true);
    expect(reconcileStaleReplace(device(), device()).pushInvalid).toBe(false);
  });
  it("takes the later lastSeenAt", () => {
    expect(reconcileStaleReplace(device({ lastSeenAt: "2026-10-07T10:00:00Z" }), device()).lastSeenAt).toBe("2026-10-07T10:00:00Z");
    expect(reconcileStaleReplace(device(), device({ lastSeenAt: "2026-10-07T10:00:00Z" })).lastSeenAt).toBe("2026-10-07T10:00:00Z");
  });
});

describe("InMemoryDeviceRepo ETag semantics (mirrors TableDeviceRepo)", () => {
  async function seeded() {
    const repo = new InMemoryDeviceRepo();
    repo.seed("u1", device());
    return repo;
  }

  it("reads carry an etag that changes on every write", async () => {
    const repo = await seeded();
    const first = await repo.getDevice("u1", "d1");
    await repo.touchLastSeen("u1", "d1", "2026-10-07T10:00:00Z");
    const second = await repo.getDevice("u1", "d1");
    expect(first?.etag).toBeTruthy();
    expect(second?.etag).not.toBe(first?.etag);
  });

  it("claimNudge with the current etag wins once; the same etag again loses", async () => {
    const repo = await seeded();
    const etag = (await repo.getDevice("u1", "d1"))?.etag as string;
    expect(await repo.claimNudge("u1", "d1", "2026-10-07T10:00:00Z", etag)).toBe(true);
    expect(await repo.claimNudge("u1", "d1", "2026-10-07T10:00:01Z", etag)).toBe(false);
    expect((await repo.getDevice("u1", "d1"))?.lastNudgedAt).toBe("2026-10-07T10:00:00Z");
  });

  it("claimNudge on a removed row is false and creates nothing", async () => {
    const repo = await seeded();
    const etag = (await repo.getDevice("u1", "d1"))?.etag as string;
    await repo.deleteDevice("u1", "d1");
    expect(await repo.claimNudge("u1", "d1", "2026-10-07T10:00:00Z", etag)).toBe(false);
    expect(await repo.getDevice("u1", "d1")).toBeNull();
  });

  it("a stale-snapshot replace cannot revert a concurrent lastNudgedAt claim", async () => {
    const repo = await seeded();
    const snapshot = (await repo.getDevice("u1", "d1")) as DeviceRecord;
    const etag = snapshot.etag as string;
    await repo.claimNudge("u1", "d1", "2026-10-07T10:00:00Z", etag);

    const written = await repo.replaceExistingDevice("u1", { ...snapshot, deviceName: "Renamed" });

    expect(written).toBe(true);
    const stored = await repo.getDevice("u1", "d1");
    expect(stored?.deviceName).toBe("Renamed");
    expect(stored?.lastNudgedAt).toBe("2026-10-07T10:00:00Z");
  });

  it("a stale-snapshot pushInvalid write-back cannot revert a concurrent markPushInvalid either way round", async () => {
    const repo = await seeded();
    const snapshot = (await repo.getDevice("u1", "d1")) as DeviceRecord;
    await repo.markPushInvalid("u1", "d1");
    await repo.replaceExistingDevice("u1", { ...snapshot, deviceName: "Renamed" });
    expect((await repo.getDevice("u1", "d1"))?.pushInvalid).toBe(true);
  });

  it("a replace on a removed row is still false (no resurrection)", async () => {
    const repo = await seeded();
    const snapshot = (await repo.getDevice("u1", "d1")) as DeviceRecord;
    await repo.deleteDevice("u1", "d1");
    expect(await repo.replaceExistingDevice("u1", snapshot)).toBe(false);
    expect(await repo.getDevice("u1", "d1")).toBeNull();
  });

  it("a replace with the current etag writes exactly the caller's record", async () => {
    const repo = await seeded();
    const snapshot = (await repo.getDevice("u1", "d1")) as DeviceRecord;
    expect(await repo.replaceExistingDevice("u1", { ...snapshot, trackingEnabled: false })).toBe(true);
    expect((await repo.getDevice("u1", "d1"))?.trackingEnabled).toBe(false);
  });
});
