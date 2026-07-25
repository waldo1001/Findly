// specs/002 §2.7 `LocateRequests` table. Integration-tested later; no unit tests here
// (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import type { LocateRequestRecord, LocateRequestRepo, LocateRequestStatus } from "../../ports/repositories";

const REQUEST_PREFIX = "req:";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function toRecord(requestId: string, familyId: string, entity: Record<string, unknown>): LocateRequestRecord {
  return {
    requestId,
    familyId,
    targetUserId: String(entity.targetUserId),
    targetDeviceId: String(entity.targetDeviceId),
    requestedBy: String(entity.requestedBy),
    status: entity.status as LocateRequestStatus,
    createdAt: String(entity.createdAt),
    expiresAt: String(entity.expiresAt),
    fixJson: entity.fixJson != null ? String(entity.fixJson) : undefined,
  };
}

export class TableLocateRequestRepo implements LocateRequestRepo {
  private readonly client = createTableClient("LocateRequests");

  async create(record: LocateRequestRecord): Promise<void> {
    await this.client.createEntity({
      partitionKey: record.familyId,
      rowKey: `${REQUEST_PREFIX}${record.requestId}`,
      targetUserId: record.targetUserId,
      targetDeviceId: record.targetDeviceId,
      requestedBy: record.requestedBy,
      status: record.status,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
      fixJson: record.fixJson ?? null,
    });
  }

  async get(familyId: string, requestId: string): Promise<LocateRequestRecord | null> {
    try {
      const entity = await this.client.getEntity(familyId, `${REQUEST_PREFIX}${requestId}`);
      return toRecord(requestId, familyId, entity);
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  async update(familyId: string, requestId: string, patch: Partial<LocateRequestRecord>): Promise<void> {
    const { requestId: _requestId, familyId: _familyId, ...rest } = patch;
    await this.client.updateEntity(
      { partitionKey: familyId, rowKey: `${REQUEST_PREFIX}${requestId}`, ...rest },
      "Merge",
    );
  }

  async listPendingByTargetDevice(familyId: string, targetDeviceId: string): Promise<LocateRequestRecord[]> {
    const records: LocateRequestRecord[] = [];
    const entities = this.client.listEntities({
      queryOptions: {
        filter: odata`PartitionKey eq ${familyId} and RowKey ge ${REQUEST_PREFIX} and RowKey lt ${"req;"} and status eq ${"pending"} and targetDeviceId eq ${targetDeviceId}`,
      },
    });
    for await (const entity of entities) {
      const requestId = String(entity.rowKey).slice(REQUEST_PREFIX.length);
      records.push(toRecord(requestId, familyId, entity));
    }
    return records;
  }

  /** Wipes every `req:` row in the family's partition, regardless of status — family
   * deletion (002 §4.2 step 3, B19). Idempotent. */
  async deletePartition(familyId: string): Promise<void> {
    const rowKeys: string[] = [];
    const entities = this.client.listEntities({
      queryOptions: {
        filter: odata`PartitionKey eq ${familyId} and RowKey ge ${REQUEST_PREFIX} and RowKey lt ${"req;"}`,
      },
    });
    for await (const entity of entities) {
      rowKeys.push(String(entity.rowKey));
    }
    await Promise.all(
      rowKeys.map((rk) =>
        this.client.deleteEntity(familyId, rk).catch((err) => {
          if (!isNotFound(err)) throw err;
        }),
      ),
    );
  }

  /** Deletes rows in the family partition where `requestedBy` OR `targetUserId` is the
   * subject — account deletion (001 §13.2, 002 §4.2 step 4, B18). A single-partition scan,
   * same idiom as listPendingByTargetDevice/deletePartition. Idempotent. */
  async deleteRowsForUser(familyId: string, userId: string): Promise<void> {
    const rowKeys: string[] = [];
    const entities = this.client.listEntities({
      queryOptions: {
        filter: odata`PartitionKey eq ${familyId} and RowKey ge ${REQUEST_PREFIX} and RowKey lt ${"req;"} and (requestedBy eq ${userId} or targetUserId eq ${userId})`,
      },
    });
    for await (const entity of entities) {
      rowKeys.push(String(entity.rowKey));
    }
    await Promise.all(
      rowKeys.map((rk) =>
        this.client.deleteEntity(familyId, rk).catch((err) => {
          if (!isNotFound(err)) throw err;
        }),
      ),
    );
  }
}
