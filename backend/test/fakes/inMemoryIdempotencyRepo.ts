import type { IdempotencyRepo } from "../../src/ports/repositories";

export class InMemoryIdempotencyRepo implements IdempotencyRepo {
  private readonly batchMarkers = new Map<string, { receivedAt: string; fixCount: number }>();
  private readonly eventMarkers = new Set<string>();
  private readonly fixMarkers = new Set<string>();

  private key(deviceId: string, id: string): string {
    return `${deviceId}|${id}`;
  }

  /** Test inspection helper: the meta actually passed to the last insert for (deviceId, batchId). */
  getBatchMarkerMeta(deviceId: string, batchId: string): { receivedAt: string; fixCount: number } | undefined {
    return this.batchMarkers.get(this.key(deviceId, batchId));
  }

  /** Test-only, read-only inspection helper (no side effects, unlike the tryInsert* probes):
   * whether ANY marker (batch/event/fix) still exists in this deviceId's partition. */
  hasAnyMarker(deviceId: string): boolean {
    const prefix = `${deviceId}|`;
    const hasIn = (keys: Iterable<string>): boolean => {
      for (const key of keys) {
        if (key.startsWith(prefix)) return true;
      }
      return false;
    };
    return hasIn(this.batchMarkers.keys()) || hasIn(this.eventMarkers) || hasIn(this.fixMarkers);
  }

  async tryInsertBatchMarker(
    deviceId: string,
    batchId: string,
    meta: { receivedAt: string; fixCount: number },
  ): Promise<boolean> {
    const key = this.key(deviceId, batchId);
    if (this.batchMarkers.has(key)) return false;
    this.batchMarkers.set(key, { ...meta });
    return true;
  }

  async tryInsertEventMarker(deviceId: string, eventId: string, _receivedAt: string): Promise<boolean> {
    const key = this.key(deviceId, eventId);
    if (this.eventMarkers.has(key)) return false;
    this.eventMarkers.add(key);
    return true;
  }

  async tryInsertFixMarker(deviceId: string, fixId: string, _receivedAt: string): Promise<boolean> {
    const key = this.key(deviceId, fixId);
    if (this.fixMarkers.has(key)) return false;
    this.fixMarkers.add(key);
    return true;
  }

  /** Account deletion (002 §4.2 step 3, B18): wipes every batch:/event:/fix: row across this
   * one deviceId's partition. Idempotent. */
  async deletePartition(deviceId: string): Promise<void> {
    const prefix = `${deviceId}|`;
    for (const key of this.batchMarkers.keys()) {
      if (key.startsWith(prefix)) this.batchMarkers.delete(key);
    }
    for (const key of this.eventMarkers) {
      if (key.startsWith(prefix)) this.eventMarkers.delete(key);
    }
    for (const key of this.fixMarkers) {
      if (key.startsWith(prefix)) this.fixMarkers.delete(key);
    }
  }
}
