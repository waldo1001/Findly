import type { UsageMetric, UsageRepo, UsageRow } from "../../src/ports/repositories";

export class InMemoryUsageRepo implements UsageRepo {
  private readonly counts = new Map<string, number>();

  private key(familyId: string, metric: UsageMetric, date: string): string {
    return `${familyId}|${date}|${metric}`;
  }

  async increment(familyId: string, metric: UsageMetric, date: string, by = 1): Promise<void> {
    const key = this.key(familyId, metric, date);
    this.counts.set(key, (this.counts.get(key) ?? 0) + by);
  }

  async get(familyId: string, metric: UsageMetric, date: string): Promise<number> {
    return this.counts.get(this.key(familyId, metric, date)) ?? 0;
  }

  async listByPartition(familyId: string): Promise<UsageRow[]> {
    const prefix = `${familyId}|`;
    const rows: UsageRow[] = [];
    for (const [key, count] of this.counts.entries()) {
      if (!key.startsWith(prefix)) continue;
      const [date, metric] = key.slice(prefix.length).split("|") as [string, UsageMetric];
      rows.push({ date, metric, count });
    }
    return rows;
  }

  async deletePartition(familyId: string): Promise<void> {
    const prefix = `${familyId}|`;
    for (const key of [...this.counts.keys()]) {
      if (key.startsWith(prefix)) {
        this.counts.delete(key);
      }
    }
  }
}
