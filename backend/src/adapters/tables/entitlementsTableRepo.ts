// specs/002 §2.6 `Entitlements` table. Integration-tested later; no unit tests here
// (thin adapter, excluded from mutation).

import { RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import type { EntitlementsRecord, EntitlementsRepo } from "../../ports/repositories";
import type { SubscriptionStatus } from "../../domain/plan";

const ENTITLEMENT_ROW_KEY = "entitlement";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

export class TableEntitlementsRepo implements EntitlementsRepo {
  private readonly client = createTableClient("Entitlements");

  async create(familyId: string, subscriptionStatus: SubscriptionStatus, updatedAt: string): Promise<void> {
    await this.client.createEntity({
      partitionKey: familyId,
      rowKey: ENTITLEMENT_ROW_KEY,
      subscriptionStatus,
      updatedAt,
    });
  }

  async get(familyId: string): Promise<EntitlementsRecord | null> {
    try {
      const entity = await this.client.getEntity(familyId, ENTITLEMENT_ROW_KEY);
      return {
        subscriptionStatus: entity.subscriptionStatus as SubscriptionStatus,
        updatedAt: String(entity.updatedAt),
      };
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  /** Idempotent (002 §4.2 step 3 — family deletion, B19). */
  async delete(familyId: string): Promise<void> {
    try {
      await this.client.deleteEntity(familyId, ENTITLEMENT_ROW_KEY);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }
}
