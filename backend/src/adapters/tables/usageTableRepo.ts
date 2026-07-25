// specs/002 §2.9 `Usage` table. Read -> +n -> ETag-guarded merge, retry loop (max 3,
// then log-and-drop — usage is telemetry, not billing). Integration-tested later; no
// unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
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
    const rows: UsageRow[] = [];
    const entities = this.client.listEntities({
      queryOptions: { filter: odata`PartitionKey eq ${familyId}` },
    });
    for await (const entity of entities) {
      const rk = String(entity.rowKey);
      const sep = rk.indexOf(":");
      rows.push({
        date: rk.slice(0, sep),
        metric: rk.slice(sep + 1) as UsageMetric,
        count: Number(entity.count ?? 0),
      });
    }
    return rows;
  }
}
