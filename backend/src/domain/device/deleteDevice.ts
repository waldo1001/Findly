// specs/001 §4.4, 011 §1 — remove a device. Pure domain logic: no Azure/Google imports.
//
// Resolution is §4.3's: the caller's own partition first, then — for any family caller — the
// family-wide per-member scan. A parent may remove any family device, an owner their own in
// every role; anyone else is AUTH_FORBIDDEN. Unknown / other-family / already-removed is
// DEVICE_NOT_FOUND. Deletion order is normative (002 §2.4): Devices row (device-originated
// calls now fail DEVICE_NOT_FOUND, ingest stops), then LastKnown, then the device's
// IdempotencyMarkers partition. History and GroupLastKnown are deliberately untouched.

import { AppError } from "../../http/errors";
import type { DeviceRepo, FamilyRepo, IdempotencyRepo, LastKnownRepo, Role } from "../../ports/repositories";
import { findDeviceInFamily } from "../family/deviceFanout";

export interface DeleteDeviceDeps {
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  lastKnownRepo: LastKnownRepo;
  idempotencyRepo: IdempotencyRepo;
}

export interface DeleteDeviceInput {
  uid: string;
  familyId: string | null;
  role: Role | null;
  deviceId: string;
}

/** Bare 204 (001 §4.4) — no response body. */
export async function deleteDevice(input: DeleteDeviceInput, deps: DeleteDeviceDeps): Promise<void> {
  let device = await deps.deviceRepo.getDevice(input.uid, input.deviceId);
  if (!device && input.familyId) {
    const members = await deps.familyRepo.listMembers(input.familyId);
    device = await findDeviceInFamily(members, input.deviceId, deps.deviceRepo);
  }
  if (!device) {
    throw new AppError("DEVICE_NOT_FOUND", "unknown deviceId");
  }

  const isOwner = device.ownerUserId === input.uid;
  if (!isOwner && input.role !== "parent") {
    throw new AppError("AUTH_FORBIDDEN", "caller is neither a parent nor the device owner");
  }

  await deps.deviceRepo.deleteDevice(device.ownerUserId, device.deviceId);
  await deps.lastKnownRepo.delete(device.ownerUserId, device.deviceId);
  await deps.idempotencyRepo.deletePartition(device.deviceId);
}
