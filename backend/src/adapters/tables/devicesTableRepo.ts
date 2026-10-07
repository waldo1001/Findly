// specs/002 §2.4 `Devices` table — keyed by owner (B8 re-key). Integration-tested later;
// no unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { DevicePlatform, DeviceRecord, DeviceRepo } from "../../ports/repositories";

const DEVICE_PREFIX = "device:";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
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
   * since the caller read it, so nothing is written and the row is never resurrected. */
  async replaceExistingDevice(ownerUserId: string, device: DeviceRecord): Promise<boolean> {
    try {
      await this.client.updateEntity(this.toEntity(ownerUserId, device), "Replace");
      return true;
    } catch (err) {
      if (isNotFound(err)) return false;
      throw err;
    }
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
