// specs/002 §2.12 `GroupLastKnown` table — keyed by groupId, `member:{userId}` rows.
// Integration-tested later against Azurite; no unit tests here (thin adapter, excluded
// from mutation). Mirrors src/adapters/tables/lastKnownTableRepo.ts's only-newer idiom.

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { GroupLastKnownRecord, GroupLastKnownRepo } from "../../ports/repositories";

const MEMBER_PREFIX = "member:";
const MAX_RETRIES = 1; // one retry on ETag race (002 §2.12, same idiom as §2.5); second loss = skip.

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && (err.statusCode === 412 || err.statusCode === 409);
}

function toRecord(userId: string, entity: Record<string, unknown>): GroupLastKnownRecord {
  return {
    userId,
    lat: Number(entity.lat),
    lon: Number(entity.lon),
    accuracyM: Number(entity.accuracyM),
    recordedAt: String(entity.recordedAt),
    receivedAt: String(entity.receivedAt),
    syncIntervalMinutes: Number(entity.syncIntervalMinutes),
  };
}

export class TableGroupLastKnownRepo implements GroupLastKnownRepo {
  private readonly client = createTableClient("GroupLastKnown");

  async upsertIfNewer(groupId: string, record: GroupLastKnownRecord): Promise<boolean> {
    const rowKey = `${MEMBER_PREFIX}${record.userId}`;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
      let existingEtag: string | undefined;
      try {
        const entity = await this.client.getEntity(groupId, rowKey);
        if (new Date(String(entity.recordedAt)).getTime() >= new Date(record.recordedAt).getTime()) {
          return false; // stored is already the same age or newer.
        }
        existingEtag = entity.etag;
      } catch (err) {
        if (!isNotFound(err)) throw err;
      }

      const entity = {
        partitionKey: groupId,
        rowKey,
        lat: record.lat,
        lon: record.lon,
        accuracyM: record.accuracyM,
        recordedAt: record.recordedAt,
        receivedAt: record.receivedAt,
        syncIntervalMinutes: record.syncIntervalMinutes,
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

  async listByGroup(groupId: string): Promise<GroupLastKnownRecord[]> {
    // 002 §4.2 (B20) — a GroupLastKnown table that has never been created (no member of this
    // group has ever posted a position) resolves to no rows.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: {
          filter: odata`PartitionKey eq ${groupId} and RowKey ge ${MEMBER_PREFIX} and RowKey lt ${"member;"}`,
        },
      }),
    );
    return entities.map((entity) => {
      const userId = String(entity.rowKey).slice(MEMBER_PREFIX.length);
      return toRecord(userId, entity);
    });
  }

  async removeMember(groupId: string, userId: string): Promise<void> {
    try {
      await this.client.deleteEntity(groupId, `${MEMBER_PREFIX}${userId}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async deletePartition(groupId: string): Promise<void> {
    // Every row in this partition belongs to groupId by construction (002 §2.12) — no
    // per-row filter needed, just wipe the whole partition (same idiom as
    // devicesTableRepo.deleteDevicesByOwner).
    const positions = await this.listByGroup(groupId);
    await Promise.all(
      positions.map((position) =>
        this.client.deleteEntity(groupId, `${MEMBER_PREFIX}${position.userId}`).catch((err) => {
          if (!isNotFound(err)) throw err;
        }),
      ),
    );
  }
}
