// specs/001 §4.1 response shape (also §4.3's "updated device object (§4.1 shape)"). Pure
// domain logic: no Azure/Google imports. Push tokens are write-only (§4.1) — never surfaced.

import type { DeviceRecord } from "../../ports/repositories";

export type DeviceView = Omit<
  DeviceRecord,
  "registeredAt" | "lastSeenAt" | "locationPushToken" | "pushToken" | "staleNudgeEnabled" | "lastNudgedAt"
> & {
  /** 001 §4.1 — always a boolean; a row without the property reads as true (002 §2.4). */
  staleNudgeEnabled: boolean;
};

export function toDeviceView(device: DeviceRecord): DeviceView {
  return {
    deviceId: device.deviceId,
    ownerUserId: device.ownerUserId,
    platform: device.platform,
    model: device.model,
    appVersion: device.appVersion,
    deviceName: device.deviceName,
    pushInvalid: device.pushInvalid,
    syncIntervalMinutes: device.syncIntervalMinutes,
    trackingEnabled: device.trackingEnabled,
    staleNudgeEnabled: device.staleNudgeEnabled !== false,
  };
}
