// specs/002 §2.13 `GroupExpiry` table — the sweeper's index. Integration-tested later; no
// unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { GroupExpiryAction, GroupExpiryRepo, GroupExpiryRow } from "../../ports/repositories";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

export class TableGroupExpiryRepo implements GroupExpiryRepo {
  private readonly client = createTableClient("GroupExpiry");

  async putExpiryRow(bucketDate: string, groupId: string, action: GroupExpiryAction): Promise<void> {
    // Upsert (not a conditional insert): B10's re-bucket-on-PATCH and B12's sweeper both
    // need to write/move this row idempotently (002 §2.13/§4.1) — this task only ever
    // writes it once at create, but the write itself has no collision to guard against.
    await this.client.upsertEntity(
      { partitionKey: bucketDate, rowKey: groupId, action },
      "Replace",
    );
  }

  async deleteExpiryRow(bucketDate: string, groupId: string): Promise<void> {
    // Swallow 404: the row may already be at a different bucket (a prior partial move or a
    // sweeper pass) — this is the self-healing no-op the port contract documents (002 §2.13).
    try {
      await this.client.deleteEntity(bucketDate, groupId);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async listByDate(bucketDate: string): Promise<GroupExpiryRow[]> {
    // The sweeper's bucket walk (002 §2.13/§4.1): a single tiny partition scan per date, never
    // a full table scan. Tolerates a GroupExpiry table that has never been created — a
    // deployment that has never had a single group (B20) — resolving to no rows rather than
    // crashing the whole daily timer run.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: { filter: odata`PartitionKey eq ${bucketDate}` },
      }),
    );
    return entities.map((entity) => ({ groupId: String(entity.rowKey), action: entity.action as GroupExpiryAction }));
  }
}
