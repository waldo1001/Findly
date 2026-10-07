// specs/001 §4.2 — list devices. Pure domain logic: no Azure/Google imports. Open family:
// every member sees every device (settings-changes are still parent-gated, §4.3). A
// family-less caller gets their own devices only (same response shape, §1.5 step 4).

import { AppError } from "../../http/errors";
import type { DeviceRepo, EntitlementsRepo, FamilyRepo, UserRepo } from "../../ports/repositories";
import { getFeatures, type Features } from "../plan";
import { listDevicesForMembers } from "../family/deviceFanout";
import type { Clock } from "../../ports/support";
import { isDormant } from "./dormancy";
import { toDeviceView, type DeviceView } from "./deviceView";

export interface ListMyDevicesDeps {
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  userRepo: UserRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface ListMyDevicesInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
}

export type DeviceListEntry = DeviceView & { ownerDisplayName: string; lastSeenAt: string; isDormant: boolean };

export interface ListMyDevicesResult {
  devices: DeviceListEntry[];
  features: Features;
}

export async function listMyDevices(input: ListMyDevicesInput, deps: ListMyDevicesDeps): Promise<ListMyDevicesResult> {
  const now = deps.clock.now();
  if (input.familyId) {
    const familyId = input.familyId;
    const entitlements = await deps.entitlementsRepo.get(familyId);
    if (!entitlements) {
      throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
    }
    const features = getFeatures(entitlements.subscriptionStatus);

    const members = await deps.familyRepo.listMembers(familyId);
    const displayNameByUserId = new Map(members.map((m) => [m.userId, m.displayName]));
    // Devices are keyed by ownerUserId, not familyId (002 §2.4, B8 re-key): fan out one
    // small partition scan per member instead of a single shared family scan.
    const devices = await listDevicesForMembers(members, deps.deviceRepo);

    return {
      devices: devices.map((device) => ({
        ...toDeviceView(device),
        ownerDisplayName: displayNameByUserId.get(device.ownerUserId) ?? device.ownerUserId,
        lastSeenAt: device.lastSeenAt,
        isDormant: isDormant(device, now),
      })),
      features,
    };
  }

  // Family-less caller (§1.5 step 4, §4.2): own devices only, own uid partition (002 §2.4).
  const profile = await deps.userRepo.getProfile(input.uid);
  const ownerDisplayName = profile?.displayName ?? input.uid;
  const devices = await deps.deviceRepo.listDevices(input.uid);
  const features = getFeatures("free");

  return {
    devices: devices.map((device) => ({
      ...toDeviceView(device),
      ownerDisplayName,
      lastSeenAt: device.lastSeenAt,
      isDormant: isDormant(device, now),
    })),
    features,
  };
}
