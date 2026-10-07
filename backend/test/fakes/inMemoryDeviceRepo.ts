import { reconcileStaleReplace } from "../../src/domain/device/deviceWrite";
import type { DeviceRecord, DeviceRepo } from "../../src/ports/repositories";

interface Row {
  device: DeviceRecord;
  version: number;
}

const MAX_REPLACE_ATTEMPTS = 5;

// specs/002 §2.4 — Devices keyed by owner (B8 re-key): every partition is one user's own
// devices, so a "delete all devices for this owner" (001 §3.6) is simply clearing that
// whole partition — no per-row ownerUserId filter needed anymore.
//
// Mirrors TableDeviceRepo's ETag semantics (002 §4.3): every write bumps a per-row version,
// reads expose it as `etag`, `claimNudge` and `replaceExistingDevice` are conditional on it.
export class InMemoryDeviceRepo implements DeviceRepo {
  private readonly devices = new Map<string, Map<string, Row>>();
  private versionCounter = 0;

  private partition(ownerUserId: string): Map<string, Row> {
    let roster = this.devices.get(ownerUserId);
    if (!roster) {
      roster = new Map();
      this.devices.set(ownerUserId, roster);
    }
    return roster;
  }

  private store(ownerUserId: string, device: DeviceRecord): void {
    const { etag: _ignored, ...persisted } = device;
    this.versionCounter += 1;
    this.partition(ownerUserId).set(device.deviceId, { device: persisted, version: this.versionCounter });
  }

  private view(row: Row): DeviceRecord {
    return { ...row.device, etag: String(row.version) };
  }

  seed(ownerUserId: string, device: DeviceRecord): void {
    this.store(ownerUserId, device);
  }

  async getDevice(ownerUserId: string, deviceId: string): Promise<DeviceRecord | null> {
    const row = this.devices.get(ownerUserId)?.get(deviceId);
    return row ? this.view(row) : null;
  }

  async putDevice(ownerUserId: string, device: DeviceRecord): Promise<void> {
    this.store(ownerUserId, device);
  }

  /** Update-only full write, ETag-guarded on `device.etag` (002 §4.3): false when the row is
   * gone; on a version mismatch re-reads and retries (bounded) with reconcileStaleReplace. */
  async replaceExistingDevice(ownerUserId: string, device: DeviceRecord): Promise<boolean> {
    let candidate = device;
    for (let attempt = 0; attempt < MAX_REPLACE_ATTEMPTS; attempt += 1) {
      const row = this.partition(ownerUserId).get(candidate.deviceId);
      if (!row) return false;
      if (candidate.etag === undefined || candidate.etag === String(row.version)) {
        this.store(ownerUserId, candidate);
        return true;
      }
      candidate = reconcileStaleReplace(this.view(row), candidate);
    }
    throw new Error("replaceExistingDevice: too many concurrent writers");
  }

  /** Mirrors TableDeviceRepo.touchLastSeen's field-level Merge semantics: merges
   * `lastSeenAt` into whatever is CURRENTLY stored, never into a caller-held snapshot — so
   * a concurrent settings change committed after a caller's own read is preserved. */
  async touchLastSeen(ownerUserId: string, deviceId: string, lastSeenAt: string): Promise<void> {
    const row = this.partition(ownerUserId).get(deviceId);
    if (!row) return;
    this.store(ownerUserId, { ...row.device, lastSeenAt });
  }

  async listDevices(ownerUserId: string): Promise<DeviceRecord[]> {
    const roster = this.devices.get(ownerUserId);
    return roster ? [...roster.values()].map((row) => this.view(row)) : [];
  }

  async listAllDevices(): Promise<DeviceRecord[]> {
    return [...this.devices.values()].flatMap((roster) => [...roster.values()].map((row) => this.view(row)));
  }

  /** Mirrors TableDeviceRepo.claimNudge: conditional (If-Match etag), update-only one-field Merge. */
  async claimNudge(ownerUserId: string, deviceId: string, lastNudgedAt: string, etag: string): Promise<boolean> {
    const row = this.partition(ownerUserId).get(deviceId);
    if (!row) return false;
    if (String(row.version) !== etag) return false;
    this.store(ownerUserId, { ...row.device, lastNudgedAt });
    return true;
  }

  /** Mirrors TableDeviceRepo.markPushInvalid: unconditional update-only one-field Merge. */
  async markPushInvalid(ownerUserId: string, deviceId: string): Promise<void> {
    const row = this.partition(ownerUserId).get(deviceId);
    if (!row) return;
    this.store(ownerUserId, { ...row.device, pushInvalid: true });
  }

  async countDevices(ownerUserId: string): Promise<number> {
    return this.devices.get(ownerUserId)?.size ?? 0;
  }

  /** Single-row delete (001 §4.4, 002 §2.4 removal step 1). Idempotent. */
  async deleteDevice(ownerUserId: string, deviceId: string): Promise<void> {
    this.devices.get(ownerUserId)?.delete(deviceId);
  }

  async deleteDevicesByOwner(ownerUserId: string): Promise<void> {
    this.devices.delete(ownerUserId);
  }
}
