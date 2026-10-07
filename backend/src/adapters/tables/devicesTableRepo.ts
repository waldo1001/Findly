// specs/002 §2.4 `Devices` table — keyed by owner (B8 re-key). Integration-tested later;
// no unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { reconcileStaleReplace } from "../../domain/device/deviceWrite";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { DevicePlatform, DeviceRecord, DeviceRepo } from "../../ports/repositories";

const DEVICE_PREFIX = "device:";
/** Bound on re-read-and-retry after a 412 in replaceExistingDevice (002 §4.3). */
const MAX_REPLACE_ATTEMPTS = 5;

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 412;
}

function toRecord(deviceId: string, entity: Record<string, unknown>): DeviceRecord {
  return {
    deviceId,
    ownerUserId: String(entity.ownerUserId),
    platform: entity.platform as DevicePlatform,
    model: String(entity.model),
    appVersion: String(entity.appVersion),
    deviceName: String(entity.deviceName),
    pushToken: entity.pushToken != null ? String(entity.pushToken) : undefined,
    locationPushToken: entity.locationPushToken != null ? String(entity.locationPushToken) : undefined,
    pushInvalid: Boolean(entity.pushInvalid),
    syncIntervalMinutes: Number(entity.syncIntervalMinutes),
    trackingEnabled: Boolean(entity.trackingEnabled),
    registeredAt: String(entity.registeredAt),
    // 001 §5.2 / 002 §2.4: a row without lastSeenAt falls back to registeredAt.
    lastSeenAt: entity.lastSeenAt != null ? String(entity.lastSeenAt) : String(entity.registeredAt),
    // 002 §2.4: a row without the property reads as true (no backfill).
    staleNudgeEnabled: entity.staleNudgeEnabled == null ? true : Boolean(entity.staleNudgeEnabled),
    lastNudgedAt: entity.lastNudgedAt != null ? String(entity.lastNudgedAt) : undefined,
    etag: typeof entity.etag === "string" ? entity.etag : undefined,
  };
}

export class TableDeviceRepo implements DeviceRepo {
  private readonly client = createTableClient("Devices");

  async getDevice(ownerUserId: string, deviceId: string): Promise<DeviceRecord | null> {
    try {
      const entity = await this.client.getEntity(ownerUserId, `${DEVICE_PREFIX}${deviceId}`);
      return toRecord(deviceId, entity);
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  private toEntity(ownerUserId: string, device: DeviceRecord) {
    return {
      partitionKey: ownerUserId,
      rowKey: `${DEVICE_PREFIX}${device.deviceId}`,
      ownerUserId: device.ownerUserId,
      platform: device.platform,
      model: device.model,
      appVersion: device.appVersion,
      deviceName: device.deviceName,
      pushToken: device.pushToken ?? null,
      locationPushToken: device.locationPushToken ?? null,
      pushInvalid: device.pushInvalid,
      syncIntervalMinutes: device.syncIntervalMinutes,
      trackingEnabled: device.trackingEnabled,
      registeredAt: device.registeredAt,
      lastSeenAt: device.lastSeenAt,
      staleNudgeEnabled: device.staleNudgeEnabled ?? true,
      lastNudgedAt: device.lastNudgedAt ?? null,
    };
  }

  async putDevice(ownerUserId: string, device: DeviceRecord): Promise<void> {
    await this.client.upsertEntity(this.toEntity(ownerUserId, device), "Replace");
  }

  /** Update-only Replace (DeviceRepo.replaceExistingDevice): a 404 means the row was removed
   * since the caller read it, so nothing is written and the row is never resurrected. ETag-
   * guarded on `device.etag` (002 §4.3): a 412 means a concurrent writer (the nudger's claim or
   * pushInvalid Merge, a lastSeenAt touch, another PATCH) got in first — re-read and retry,
   * bounded, with the system-written fields carried over so they are never reverted. */
  async replaceExistingDevice(ownerUserId: string, device: DeviceRecord): Promise<boolean> {
    let candidate = device;
    for (let attempt = 0; attempt < MAX_REPLACE_ATTEMPTS; attempt += 1) {
      try {
        await this.client.updateEntity(
          this.toEntity(ownerUserId, candidate),
          "Replace",
          candidate.etag === undefined ? undefined : { etag: candidate.etag },
        );
        return true;
      } catch (err) {
        if (isNotFound(err)) return false;
        if (!isPreconditionFailed(err)) throw err;
        const fresh = await this.getDevice(ownerUserId, candidate.deviceId);
        if (fresh === null) return false;
        candidate = reconcileStaleReplace(fresh, candidate);
      }
    }
    throw new Error("replaceExistingDevice: too many concurrent writers");
  }

  /** Timestamp-only write (002 §2.4, DeviceRepo.touchLastSeen): a field-level Merge that
   * touches ONLY `lastSeenAt`, so it can never rewrite parent-managed settings from a stale
   * in-request snapshot the way a full `Replace` upsert would. */
  async touchLastSeen(ownerUserId: string, deviceId: string, lastSeenAt: string): Promise<void> {
    try {
      await this.client.updateEntity(
        {
          partitionKey: ownerUserId,
          rowKey: `${DEVICE_PREFIX}${deviceId}`,
          lastSeenAt,
        },
        "Merge",
      );
    } catch (err) {
      // A device removed mid-request (001 §4.4): Merge never resurrects a row; the caller's
      // write-time device-existence guard then abandons the batch.
      if (!isNotFound(err)) throw err;
    }
  }

  async listDevices(ownerUserId: string): Promise<DeviceRecord[]> {
    // 002 §4.2 (B20) — a Devices table that has never been created (TableNotFound) resolves
    // to no devices, same as an existing-but-empty partition.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: {
          filter: odata`PartitionKey eq ${ownerUserId} and RowKey ge ${DEVICE_PREFIX} and RowKey lt ${"device;"}`,
        },
      }),
    );
    return entities.map((entity) => {
      const deviceId = String(entity.rowKey).slice(DEVICE_PREFIX.length);
      return toRecord(deviceId, entity);
    });
  }

  /** Full scan of every owner partition (stale nudger, 002 §4.3). Only device rows — the
   * `device:` RowKey range — though today `Devices` holds nothing else. List-tolerant. */
  async listAllDevices(): Promise<DeviceRecord[]> {
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: { filter: odata`RowKey ge ${DEVICE_PREFIX} and RowKey lt ${"device;"}` },
      }),
    );
    return entities.map((entity) => toRecord(String(entity.rowKey).slice(DEVICE_PREFIX.length), entity));
  }

  /** Timestamp-only claim (002 §2.4/§4.3): ETag-conditional update-only Merge of `lastNudgedAt`
   * on the version the scan read. 412 (another run claimed, or any write intervened) and 404
   * (row removed since the scan, or table gone) write nothing and report false. */
  async claimNudge(ownerUserId: string, deviceId: string, lastNudgedAt: string, etag: string): Promise<boolean> {
    try {
      await this.client.updateEntity(
        { partitionKey: ownerUserId, rowKey: `${DEVICE_PREFIX}${deviceId}`, lastNudgedAt },
        "Merge",
        { etag },
      );
      return true;
    } catch (err) {
      if (isNotFound(err) || isPreconditionFailed(err)) return false;
      throw err;
    }
  }

  /** One-field update-only Merge of `pushInvalid: true` (001 §8.5). Tolerates a removed row. */
  async markPushInvalid(ownerUserId: string, deviceId: string): Promise<void> {
    try {
      await this.client.updateEntity(
        { partitionKey: ownerUserId, rowKey: `${DEVICE_PREFIX}${deviceId}`, pushInvalid: true },
        "Merge",
      );
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async countDevices(ownerUserId: string): Promise<number> {
    const devices = await this.listDevices(ownerUserId);
    return devices.length;
  }

  /** Single-row delete (001 §4.4, 002 §2.4 step 1). Idempotent: swallows not-found,
   * including a never-created table. */
  async deleteDevice(ownerUserId: string, deviceId: string): Promise<void> {
    try {
      await this.client.deleteEntity(ownerUserId, `${DEVICE_PREFIX}${deviceId}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async deleteDevicesByOwner(ownerUserId: string): Promise<void> {
    // Every row in this partition belongs to ownerUserId by construction (002 §2.4) — no
    // per-row filter needed, just wipe the whole partition.
    const devices = await this.listDevices(ownerUserId);
    await Promise.all(devices.map((device) => this.client.deleteEntity(ownerUserId, `${DEVICE_PREFIX}${device.deviceId}`)));
  }
}
