import type { LocateRequestRecord, LocateRequestRepo } from "../../src/ports/repositories";

export class InMemoryLocateRequestRepo implements LocateRequestRepo {
  private readonly records = new Map<string, Map<string, LocateRequestRecord>>();

  private partition(familyId: string): Map<string, LocateRequestRecord> {
    let roster = this.records.get(familyId);
    if (!roster) {
      roster = new Map();
      this.records.set(familyId, roster);
    }
    return roster;
  }

  /** Test setup helper: seeds a record bypassing normal creation. */
  seed(record: LocateRequestRecord): void {
    this.partition(record.familyId).set(record.requestId, { ...record });
  }

  async create(record: LocateRequestRecord): Promise<void> {
    this.partition(record.familyId).set(record.requestId, { ...record });
  }

  async get(familyId: string, requestId: string): Promise<LocateRequestRecord | null> {
    const record = this.records.get(familyId)?.get(requestId);
    return record ? { ...record } : null;
  }

  async update(familyId: string, requestId: string, patch: Partial<LocateRequestRecord>): Promise<void> {
    const roster = this.records.get(familyId);
    const existing = roster?.get(requestId);
    if (!roster || !existing) {
      throw new Error(`InMemoryLocateRequestRepo: no request ${requestId} in family ${familyId}`);
    }
    roster.set(requestId, { ...existing, ...patch });
  }

  async listPendingByTargetDevice(familyId: string, targetDeviceId: string): Promise<LocateRequestRecord[]> {
    const roster = this.records.get(familyId);
    if (!roster) return [];
    return [...roster.values()]
      .filter((record) => record.status === "pending" && record.targetDeviceId === targetDeviceId)
      .map((record) => ({ ...record }));
  }

  async deletePartition(familyId: string): Promise<void> {
    this.records.delete(familyId);
  }
}
