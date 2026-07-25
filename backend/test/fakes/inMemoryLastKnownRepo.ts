import type { LastKnownRecord, LastKnownRepo } from "../../src/ports/repositories";

// specs/002 §2.5 — LastKnown keyed by owner (B8 re-key): same owner-partition rule as
// InMemoryDeviceRepo.
export class InMemoryLastKnownRepo implements LastKnownRepo {
  private readonly records = new Map<string, Map<string, LastKnownRecord>>();

  private partition(ownerUserId: string): Map<string, LastKnownRecord> {
    let roster = this.records.get(ownerUserId);
    if (!roster) {
      roster = new Map();
      this.records.set(ownerUserId, roster);
    }
    return roster;
  }

  /** Seeds a record bypassing the only-newer rule (test setup helper). */
  seed(ownerUserId: string, record: LastKnownRecord): void {
    this.partition(ownerUserId).set(record.deviceId, { ...record });
  }

  async get(ownerUserId: string, deviceId: string): Promise<LastKnownRecord | null> {
    const record = this.records.get(ownerUserId)?.get(deviceId);
    return record ? { ...record } : null;
  }

  async upsertIfNewer(ownerUserId: string, record: LastKnownRecord): Promise<boolean> {
    const roster = this.partition(ownerUserId);
    const existing = roster.get(record.deviceId);
    if (existing && new Date(existing.recordedAt).getTime() >= new Date(record.recordedAt).getTime()) {
      return false;
    }
    roster.set(record.deviceId, { ...record });
    return true;
  }

  async listByOwner(ownerUserId: string): Promise<LastKnownRecord[]> {
    const roster = this.records.get(ownerUserId);
    return roster ? [...roster.values()].map((r) => ({ ...r })) : [];
  }

  /** Account deletion (002 §4.2 step 2, B18). Idempotent. */
  async deleteByOwner(ownerUserId: string): Promise<void> {
    this.records.delete(ownerUserId);
  }
}
