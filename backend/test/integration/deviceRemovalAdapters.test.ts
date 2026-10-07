// specs/001 §4.4, 011 §6, 002 §2.4 — the table-adapter mechanics device removal depends on:
// single-row deletes (leaving siblings), tolerance of a missing row AND a never-created table
// (002 §2 list-tolerance rule), the legacy-row read defaults, the staleNudgeEnabled/
// lastNudgedAt round trip, and the update-only write that keeps a removed device removed.
// Requires Azurite (`npm run dev:storage`); run via `npm run test:integration`. Drops tables,
// so it relies on `fileParallelism: false` (vitest.integration.config.ts).

import { beforeAll, describe, expect, it } from "vitest";
import { createTableClient } from "../../src/adapters/tables/tableClientFactory";
import { dropTables, ensureTables } from "./support/ensureStorage";
import { testDeviceId, testUserId } from "./support/ids";
import { TableDeviceRepo } from "../../src/adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../../src/adapters/tables/lastKnownTableRepo";
import { TableIdempotencyRepo } from "../../src/adapters/tables/idempotencyMarkersTableRepo";
import type { DeviceRecord, LastKnownRecord } from "../../src/ports/repositories";

function device(ownerUserId: string, deviceId: string, overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId,
    ownerUserId,
    platform: "android",
    model: "Pixel 8",
    appVersion: "1.0.0",
    deviceName: "Pixel 8",
    pushInvalid: false,
    syncIntervalMinutes: 15,
    trackingEnabled: true,
    registeredAt: "2026-07-01T00:00:00Z",
    lastSeenAt: "2026-07-19T09:00:00Z",
    ...overrides,
  };
}

function fix(deviceId: string): LastKnownRecord {
  return {
    deviceId,
    lat: 51.05,
    lon: 3.71,
    accuracyM: 10,
    batteryPct: 80,
    recordedAt: "2026-07-19T09:00:00Z",
    receivedAt: "2026-07-19T09:00:02Z",
    source: "periodic",
  };
}

describe("integration/device removal adapters (specs/001 §4.4, 011 §6)", () => {
  beforeAll(async () => {
    await ensureTables("Devices", "LastKnown", "IdempotencyMarkers");
  }, 30_000);

  it("DeviceRepo.deleteDevice deletes one row and leaves a sibling in the same partition", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const [a, b] = [testDeviceId(), testDeviceId()];
    await repo.putDevice(owner, device(owner, a));
    await repo.putDevice(owner, device(owner, b));

    await repo.deleteDevice(owner, a);

    expect(await repo.getDevice(owner, a)).toBeNull();
    expect(await repo.getDevice(owner, b)).not.toBeNull();
    expect(await repo.countDevices(owner)).toBe(1);
  });

  it("DeviceRepo.deleteDevice tolerates a missing row", async () => {
    await expect(new TableDeviceRepo().deleteDevice(testUserId(), testDeviceId())).resolves.toBeUndefined();
  });

  it("LastKnownRepo.delete deletes one row and leaves a sibling; tolerates a missing row", async () => {
    const repo = new TableLastKnownRepo();
    const owner = testUserId();
    const [a, b] = [testDeviceId(), testDeviceId()];
    await repo.upsertIfNewer(owner, fix(a));
    await repo.upsertIfNewer(owner, fix(b));

    await repo.delete(owner, a);
    await repo.delete(owner, a);

    expect(await repo.get(owner, a)).toBeNull();
    expect(await repo.get(owner, b)).not.toBeNull();
  });

  it("legacy Devices entity without staleNudgeEnabled and lastSeenAt reads staleNudgeEnabled true and lastSeenAt === registeredAt", async () => {
    const owner = testUserId();
    const id = testDeviceId();
    await createTableClient("Devices").upsertEntity(
      {
        partitionKey: owner,
        rowKey: `device:${id}`,
        ownerUserId: owner,
        platform: "ios",
        model: "iPhone",
        appVersion: "1.0.0",
        deviceName: "iPhone",
        pushInvalid: false,
        syncIntervalMinutes: 15,
        trackingEnabled: true,
        registeredAt: "2026-06-01T00:00:00Z",
      },
      "Replace",
    );

    const read = await new TableDeviceRepo().getDevice(owner, id);

    expect(read?.staleNudgeEnabled).toBe(true);
    expect(read?.lastSeenAt).toBe("2026-06-01T00:00:00Z");
    expect(read?.lastNudgedAt).toBeUndefined();
    const listed = await new TableDeviceRepo().listDevices(owner);
    expect(listed[0]?.staleNudgeEnabled).toBe(true);
    expect(listed[0]?.lastSeenAt).toBe("2026-06-01T00:00:00Z");
  });

  it("putDevice -> getDevice round-trips staleNudgeEnabled false and lastNudgedAt", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id, { staleNudgeEnabled: false, lastNudgedAt: "2026-07-18T10:00:00Z" }));

    const read = await repo.getDevice(owner, id);

    expect(read?.staleNudgeEnabled).toBe(false);
    expect(read?.lastNudgedAt).toBe("2026-07-18T10:00:00Z");
  });

  it("touchLastSeen on a removed device neither throws nor resurrects the row", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id));
    await repo.deleteDevice(owner, id);

    await expect(repo.touchLastSeen(owner, id, "2026-07-20T00:00:00Z")).resolves.toBeUndefined();

    expect(await repo.getDevice(owner, id)).toBeNull();
  });

  it("replaceExistingDevice writes an existing row and returns true", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id));

    const wrote = await repo.replaceExistingDevice(owner, device(owner, id, { deviceName: "Renamed" }));

    expect(wrote).toBe(true);
    expect((await repo.getDevice(owner, id))?.deviceName).toBe("Renamed");
  });

  it("replaceExistingDevice on a removed device returns false and does NOT resurrect it (PATCH-vs-DELETE race)", async () => {
    const repo = new TableDeviceRepo();
    const owner = testUserId();
    const id = testDeviceId();
    await repo.putDevice(owner, device(owner, id));
    await repo.deleteDevice(owner, id);

    const wrote = await repo.replaceExistingDevice(owner, device(owner, id, { deviceName: "Ghost" }));

    expect(wrote).toBe(false);
    expect(await repo.getDevice(owner, id)).toBeNull();
  });

  describe("never-created tables (002 §2 list-tolerance rule)", () => {
    it("DeviceRepo.deleteDevice, replaceExistingDevice and touchLastSeen tolerate a dropped Devices table", async () => {
      await dropTables("Devices");
      const repo = new TableDeviceRepo();
      const owner = testUserId();
      const id = testDeviceId();
      try {
        await expect(repo.deleteDevice(owner, id)).resolves.toBeUndefined();
        await expect(repo.replaceExistingDevice(owner, device(owner, id))).resolves.toBe(false);
        await expect(repo.touchLastSeen(owner, id, "2026-07-20T00:00:00Z")).resolves.toBeUndefined();
      } finally {
        await ensureTables("Devices");
      }
    });

    it("LastKnownRepo.delete tolerates a dropped LastKnown table", async () => {
      await dropTables("LastKnown");
      try {
        await expect(new TableLastKnownRepo().delete(testUserId(), testDeviceId())).resolves.toBeUndefined();
      } finally {
        await ensureTables("LastKnown");
      }
    });

    it("IdempotencyRepo.deletePartition tolerates a dropped IdempotencyMarkers table", async () => {
      await dropTables("IdempotencyMarkers");
      try {
        await expect(new TableIdempotencyRepo().deletePartition(testDeviceId())).resolves.toBeUndefined();
      } finally {
        await ensureTables("IdempotencyMarkers");
      }
    });
  });
});
