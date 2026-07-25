import type { EntitlementsRecord, EntitlementsRepo } from "../../src/ports/repositories";
import type { SubscriptionStatus } from "../../src/domain/plan";

export class InMemoryEntitlementsRepo implements EntitlementsRepo {
  private readonly records = new Map<string, EntitlementsRecord>();

  seed(familyId: string, record: EntitlementsRecord): void {
    this.records.set(familyId, { ...record });
  }

  async create(familyId: string, subscriptionStatus: SubscriptionStatus, updatedAt: string): Promise<void> {
    this.records.set(familyId, { subscriptionStatus, updatedAt });
  }

  async get(familyId: string): Promise<EntitlementsRecord | null> {
    const record = this.records.get(familyId);
    return record ? { ...record } : null;
  }

  async delete(familyId: string): Promise<void> {
    this.records.delete(familyId);
  }
}
