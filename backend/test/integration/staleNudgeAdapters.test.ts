// specs/002 §2.4/§4.3, 011 §4.2 — the DeviceRepo methods the staleNudger relies on, against real
// Table Storage (Azurite): the cross-owner full scan (incl. a never-created table), the
// timestamp-only update-only claim, and the one-field pushInvalid Merge. Drops tables, so it
// relies on `fileParallelism: false` (vitest.integration.config.ts).

import { beforeAll, describe, expect, it } from "vitest";
import { dropTables, ensureTables } from "./support/ensureStorage";
import { testDeviceId, testUserId } from "./support/ids";
import { TableDeviceRepo } from "../../src/adapters/tables/devicesTableRepo";
import type { DeviceRecord } from "../../src/ports/repositories";

function device(ownerUserId: string, deviceId: string, overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId,
    ownerUserId,
    platform: "ios",
    model: "iPhone 15",
    appVersion: "1.2.0",
    deviceName: "Original name",
    pushToken: "tok-original",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    staleNudgeEnabled: true,
    ...overrides,
  };
}

describe("integration/stale nudge adapters (specs/002 §2.4/§4.3, 011 §4.2)", () => {
  beforeAll(async () => {
    await ensureTables("Devices");
  }, 30_000);

  it("listAllDevices returns devices across several owner partitions", async () => {
    const repo = new TableDeviceRepo();
    const [o1, o2] = [testUserId(), testUserId()];
    const [d1, d2] = [testDeviceId(), testDeviceId()];
    await repo.putDevice(o1, device(o1, d1));
    await repo.putDevice(o2, device(o2, d2, { staleNudgeEnabled: false, lastNudgedAt: "2026-07-18T10:00:00Z" }));

    const all = await repo.listAllDevices();

    const mine = all.filter((d) => d.deviceId === d1 || d.deviceId === d2);
    expect(mine.map((d) => d.deviceId).sort()).toEqual([d1, d2].sort());
    const second = mine.find((d) => d.deviceId === d2);
    expect(second?.ownerUserId).toBe(o2);
    expect(second?.staleNudgeEnabled).toBe(false);
    expect(second?.lastNudgedAt).toBe("2026-07-18T10:00:00Z");
  });

  it("listAllDevices on a never-created Devices table resolves to []", async () => {
    await dropTables("Devices");
    try {
      expect(await new TableDeviceRepo().listAllDevices()).toEqual([]);
    } finally {
      await ensureTables("Devices");
    }
  }, 60_000);

  it("claimNudge writes ONLY lastNudgedAt and returns true", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    const before = device(owner, id);
    await repo.putDevice(owner, before);

    const claimed = await repo.claimNudge(owner, id, "2026-10-07T10:00:00Z");

    expect(claimed).toBe(true);
    expect(await repo.getDevice(owner, id)).toEqual({ ...before, lastNudgedAt: "2026-10-07T10:00:00Z" });
  });

  it("claimNudge merges into the CURRENT row, preserving a change made after the scan", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id));
    await repo.putDevice(owner, device(owner, id, { deviceName: "Renamed", syncIntervalMinutes: 30, trackingEnabled: false }));

    await repo.claimNudge(owner, id, "2026-10-07T10:00:00Z");

    const read = await repo.getDevice(owner, id);
    expect(read?.deviceName).toBe("Renamed");
    expect(read?.syncIntervalMinutes).toBe(30);
    expect(read?.trackingEnabled).toBe(false);
    expect(read?.lastNudgedAt).toBe("2026-10-07T10:00:00Z");
  });

  it("claimNudge on a removed device returns false and does not resurrect the row", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id));
    await repo.deleteDevice(owner, id);

    expect(await repo.claimNudge(owner, id, "2026-10-07T10:00:00Z")).toBe(false);
    expect(await repo.getDevice(owner, id)).toBeNull();
  });

  it("markPushInvalid sets only pushInvalid", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    const before = device(owner, id, { lastNudgedAt: "2026-10-07T10:00:00Z" });
    await repo.putDevice(owner, before);

    await repo.markPushInvalid(owner, id);

    expect(await repo.getDevice(owner, id)).toEqual({ ...before, pushInvalid: true });
  });

  it("markPushInvalid on a removed device neither throws nor resurrects the row", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id));
    await repo.deleteDevice(owner, id);

    await expect(repo.markPushInvalid(owner, id)).resolves.toBeUndefined();
    expect(await repo.getDevice(owner, id)).toBeNull();
  });
});
