// specs/002 §2.8 `IdempotencyMarkers` table. Conditional insert ("Add", fails 409 if it
// already exists, 002 §2) IS the dedupe test. Integration-tested later; no unit tests
// here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { IdempotencyRepo } from "../../ports/repositories";

function isAlreadyExists(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 409;
}

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

export class TableIdempotencyRepo implements IdempotencyRepo {
  private readonly client = createTableClient("IdempotencyMarkers");

  private async tryInsert(partitionKey: string, rowKey: string, extra: Record<string, unknown>): Promise<boolean> {
    try {
      await this.client.createEntity({ partitionKey, rowKey, ...extra });
      return true;
    } catch (err) {
      if (isAlreadyExists(err)) return false;
      throw err;
    }
  }

  async tryInsertBatchMarker(
    deviceId: string,
    batchId: string,
    meta: { receivedAt: string; fixCount: number },
  ): Promise<boolean> {
    return this.tryInsert(deviceId, `batch:${batchId}`, meta);
  }

  async tryInsertEventMarker(deviceId: string, eventId: string, receivedAt: string): Promise<boolean> {
    return this.tryInsert(deviceId, `event:${eventId}`, { receivedAt });
  }

  async tryInsertFixMarker(deviceId: string, fixId: string, receivedAt: string): Promise<boolean> {
    return this.tryInsert(deviceId, `fix:${fixId}`, { receivedAt });
  }

  /** Wipes every batch:/event:/fix: row in one deviceId's whole partition — account deletion
   * (001 §13.2, 002 §4.2 step 3, B18). No rowkey filter needed: every row in this partition
   * belongs to deviceId by construction (same idiom as devicesTableRepo.deleteDevicesByOwner).
   * Idempotent. */
  async deletePartition(deviceId: string): Promise<void> {
    // 002 §4.2 (B20) — an IdempotencyMarkers table that has never been created (e.g. a
    // device that never posted a batch/event/fix) resolves to nothing to delete.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: { filter: odata`PartitionKey eq ${deviceId}` },
      }),
    );
    const rowKeys = entities.map((entity) => String(entity.rowKey));
    await Promise.all(
      rowKeys.map((rk) =>
        this.client.deleteEntity(deviceId, rk).catch((err) => {
          if (!isNotFound(err)) throw err;
        }),
      ),
    );
  }
}
