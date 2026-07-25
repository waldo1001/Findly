// specs/002 §2.9 `Usage` table. Read -> +n -> ETag-guarded merge, retry loop (max 3,
// then log-and-drop — usage is telemetry, not billing). Integration-tested later; no
// unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { UsageMetric, UsageRepo, UsageRow } from "../../ports/repositories";

const MAX_RETRIES = 3;

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && (err.statusCode === 412 || err.statusCode === 409);
}

function rowKey(date: string, metric: UsageMetric): string {
  return `${date}:${metric}`;
}

export class TableUsageRepo implements UsageRepo {
  private readonly client = createTableClient("Usage");

  async increment(familyId: string, metric: UsageMetric, date: string, by = 1): Promise<void> {
    const rk = rowKey(date, metric);
    for (let attempt = 0; attempt < MAX_RETRIES; attempt += 1) {
      try {
        let current: { count: number; etag?: string } = { count: 0 };
        try {
          const entity = await this.client.getEntity(familyId, rk);
          current = { count: Number(entity.count ?? 0), etag: entity.etag };
        } catch (err) {
          if (!isNotFound(err)) throw err;
        }

        if (current.etag) {
          await this.client.updateEntity(
            { partitionKey: familyId, rowKey: rk, count: current.count + by },
            "Merge",
            { etag: current.etag },
          );
        } else {
          await this.client.createEntity({ partitionKey: familyId, rowKey: rk, count: by });
        }
        return;
      } catch (err) {
        if (isPreconditionFailed(err) && attempt < MAX_RETRIES - 1) {
          continue;
        }
        // Usage is telemetry, not billing (002 §2.9) — log and drop rather than fail the request.
        // Log IDs only, never payload contents (docs/security-review-checklist.md §3).
        const message = err instanceof Error ? err.message : "unknown error";
        console.error(`TableUsageRepo.increment: giving up on familyId=${familyId} row=${rk}: ${message}`);
        return;
      }
    }
  }

  async get(familyId: string, metric: UsageMetric, date: string): Promise<number> {
    try {
      const entity = await this.client.getEntity(familyId, rowKey(date, metric));
      return Number(entity.count ?? 0);
    } catch (err) {
      if (isNotFound(err)) return 0;
      throw err;
    }
  }

  // B17 (specs/001 §13.1, 008 §2) — export-only partition scan; see the UsageRepo interface
  // doc for why callers only ever invoke this for a family-less subject's own uid partition.
  async listByPartition(familyId: string): Promise<UsageRow[]> {
    // 002 §4.2 (B20) — a Usage table that has never been created resolves to no rows (export
    // walks this for a family-less subject's own uid partition, 008 §2).
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: { filter: odata`PartitionKey eq ${familyId}` },
      }),
    );
    return entities.map((entity) => {
      const rk = String(entity.rowKey);
      const sep = rk.indexOf(":");
      return {
        date: rk.slice(0, sep),
        metric: rk.slice(sep + 1) as UsageMetric,
        count: Number(entity.count ?? 0),
      };
    });
  }

  /** Wipes every row in the family's partition — every metric, every date (002 §4.2 step 3,
   * B19). No rowkey filter needed: every row in this partition belongs to familyId by
   * construction (same idiom as devicesTableRepo.deleteDevicesByOwner). Idempotent, and
   * tolerates the Usage table never having been created at all (B20). */
  async deletePartition(familyId: string): Promise<void> {
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: { filter: odata`PartitionKey eq ${familyId}` },
      }),
    );
    const rowKeys = entities.map((entity) => String(entity.rowKey));
    await Promise.all(
      rowKeys.map((rk) =>
        this.client.deleteEntity(familyId, rk).catch((err) => {
          if (!isNotFound(err)) throw err;
        }),
      ),
    );
  }
}
