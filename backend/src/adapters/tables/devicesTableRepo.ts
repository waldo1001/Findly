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
    lastSeenAt: String(entity.lastSeenAt),
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

  async putDevice(ownerUserId: string, device: DeviceRecord): Promise<void> {
    await this.client.upsertEntity(
      {
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
      },
      "Replace",
    );
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

  async deleteDevicesByOwner(ownerUserId: string): Promise<void> {
    // Every row in this partition belongs to ownerUserId by construction (002 §2.4) — no
    // per-row filter needed, just wipe the whole partition.
    const devices = await this.listDevices(ownerUserId);
    await Promise.all(devices.map((device) => this.client.deleteEntity(ownerUserId, `${DEVICE_PREFIX}${device.deviceId}`)));
  }
}
