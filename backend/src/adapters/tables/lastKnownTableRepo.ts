// specs/002 §2.5 `LastKnown` table — keyed by owner (B8 re-key). Integration-tested later;
// no unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import type { FixSource, LastKnownRecord, LastKnownRepo } from "../../ports/repositories";

const DEVICE_PREFIX = "device:";
const MAX_RETRIES = 1; // one retry on ETag race (002 §2.5); second loss = skip.

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && (err.statusCode === 412 || err.statusCode === 409);
}

function toRecord(deviceId: string, entity: Record<string, unknown>): LastKnownRecord {
  return {
    deviceId,
    lat: Number(entity.lat),
    lon: Number(entity.lon),
    accuracyM: Number(entity.accuracyM),
    altitudeM: entity.altitudeM != null ? Number(entity.altitudeM) : undefined,
    speedMps: entity.speedMps != null ? Number(entity.speedMps) : undefined,
    bearingDeg: entity.bearingDeg != null ? Number(entity.bearingDeg) : undefined,
    batteryPct: Number(entity.batteryPct),
    recordedAt: String(entity.recordedAt),
    receivedAt: String(entity.receivedAt),
    source: entity.source as FixSource,
  };
}

export class TableLastKnownRepo implements LastKnownRepo {
  private readonly client = createTableClient("LastKnown");

  async get(ownerUserId: string, deviceId: string): Promise<LastKnownRecord | null> {
    try {
      const entity = await this.client.getEntity(ownerUserId, `${DEVICE_PREFIX}${deviceId}`);
      return toRecord(deviceId, entity);
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  async upsertIfNewer(ownerUserId: string, record: LastKnownRecord): Promise<boolean> {
    const rowKey = `${DEVICE_PREFIX}${record.deviceId}`;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
      let existingEtag: string | undefined;
      try {
        const entity = await this.client.getEntity(ownerUserId, rowKey);
        if (new Date(String(entity.recordedAt)).getTime() >= new Date(record.recordedAt).getTime()) {
          return false; // stored is already the same age or newer.
        }
        existingEtag = entity.etag;
      } catch (err) {
        if (!isNotFound(err)) throw err;
      }

      const entity = {
        partitionKey: ownerUserId,
        rowKey,
        lat: record.lat,
        lon: record.lon,
        accuracyM: record.accuracyM,
        altitudeM: record.altitudeM ?? null,
        speedMps: record.speedMps ?? null,
        bearingDeg: record.bearingDeg ?? null,
        batteryPct: record.batteryPct,
        recordedAt: record.recordedAt,
        receivedAt: record.receivedAt,
        source: record.source,
      };

      try {
        if (existingEtag) {
          await this.client.updateEntity(entity, "Replace", { etag: existingEtag });
        } else {
          await this.client.createEntity(entity);
        }
        return true;
      } catch (err) {
        if (isPreconditionFailed(err) && attempt < MAX_RETRIES) {
          continue; // race: re-read and re-check "newer" on the next loop iteration.
        }
        throw err;
      }
    }
    return false;
  }

  async listByOwner(ownerUserId: string): Promise<LastKnownRecord[]> {
    const records: LastKnownRecord[] = [];
    const entities = this.client.listEntities({
      queryOptions: {
        filter: odata`PartitionKey eq ${ownerUserId} and RowKey ge ${DEVICE_PREFIX} and RowKey lt ${"device;"}`,
      },
    });
    for await (const entity of entities) {
      const deviceId = String(entity.rowKey).slice(DEVICE_PREFIX.length);
      records.push(toRecord(deviceId, entity));
    }
    return records;
  }

  /** Wipes the owner's whole partition — account deletion (001 §13.2, 002 §4.2 step 2, B18).
   * Idempotent. */
  async deleteByOwner(ownerUserId: string): Promise<void> {
    const records = await this.listByOwner(ownerUserId);
    await Promise.all(
      records.map((record) =>
        this.client.deleteEntity(ownerUserId, `${DEVICE_PREFIX}${record.deviceId}`).catch((err) => {
          if (!isNotFound(err)) throw err;
        }),
      ),
    );
  }
}
