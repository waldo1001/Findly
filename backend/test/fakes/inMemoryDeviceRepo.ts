import type { DeviceRecord, DeviceRepo } from "../../src/ports/repositories";

// specs/002 §2.4 — Devices keyed by owner (B8 re-key): every partition is one user's own
// devices, so a "delete all devices for this owner" (001 §3.6) is simply clearing that
// whole partition — no per-row ownerUserId filter needed anymore.
export class InMemoryDeviceRepo implements DeviceRepo {
  private readonly devices = new Map<string, Map<string, DeviceRecord>>();

  private partition(ownerUserId: string): Map<string, DeviceRecord> {
    let roster = this.devices.get(ownerUserId);
    if (!roster) {
      roster = new Map();
      this.devices.set(ownerUserId, roster);
    }
    return roster;
  }

  seed(ownerUserId: string, device: DeviceRecord): void {
    this.partition(ownerUserId).set(device.deviceId, { ...device });
  }

  async getDevice(ownerUserId: string, deviceId: string): Promise<DeviceRecord | null> {
    const device = this.devices.get(ownerUserId)?.get(deviceId);
    return device ? { ...device } : null;
  }

  async putDevice(ownerUserId: string, device: DeviceRecord): Promise<void> {
    this.partition(ownerUserId).set(device.deviceId, { ...device });
  }

  /** Mirrors TableDeviceRepo.touchLastSeen's field-level Merge semantics: merges
   * `lastSeenAt` into whatever is CURRENTLY stored, never into a caller-held snapshot — so
   * a concurrent settings change committed after a caller's own read is preserved. */
  async touchLastSeen(ownerUserId: string, deviceId: string, lastSeenAt: string): Promise<void> {
    const roster = this.partition(ownerUserId);
    const current = roster.get(deviceId);
    if (!current) return;
    roster.set(deviceId, { ...current, lastSeenAt });
  }

  async listDevices(ownerUserId: string): Promise<DeviceRecord[]> {
    const roster = this.devices.get(ownerUserId);
    return roster ? [...roster.values()].map((d) => ({ ...d })) : [];
  }

  async countDevices(ownerUserId: string): Promise<number> {
    return this.devices.get(ownerUserId)?.size ?? 0;
  }

  async deleteDevicesByOwner(ownerUserId: string): Promise<void> {
    this.devices.delete(ownerUserId);
  }
}
