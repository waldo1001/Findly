// specs/001 §4.3 — update device settings. Pure domain logic: no Azure/Google imports.
//
// Role matrix (§4.3): a parent may set any field of any family device; a non-parent owner
// (member role, in a family) may set only pushToken and staleNudgeEnabled on their OWN device — any other field
// is AUTH_FORBIDDEN, and so is targeting a device they don't own; a family-less owner may
// set any field of their own device (no family => no parent => the user is their own admin,
// §1.5 step 4). Devices are keyed by ownerUserId, not familyId (002 §2.4, B8 re-key): the
// device is first looked up in the CALLER's own partition (covers the common case — own
// device, any role); only when that misses AND the caller has a family do we fan out across
// every family member's partition (src/domain/family/deviceFanout.ts) to find a device that
// belongs to someone else — the only way a parent can reach another member's device. A
// family-less caller never has a family to fan out over, so they can never even reference
// another user's deviceId (DEVICE_NOT_FOUND).

import { AppError } from "../../http/errors";
import { parseOrThrow, patchDeviceSettingsRequestSchema } from "../../http/validate";
import type { DeviceRecord, DeviceRepo, EntitlementsRepo, FamilyRepo, Role } from "../../ports/repositories";
import type { PushSender } from "../../ports/pushSender";
import { getFeatures, type Features } from "../plan";
import { findDeviceInFamily } from "../family/deviceFanout";
import { toDeviceView, type DeviceView } from "./deviceView";

export interface PatchDeviceSettingsDeps {
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  entitlementsRepo: EntitlementsRepo;
  pushSender: PushSender;
}

export interface PatchDeviceSettingsInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  /** The caller's role from the resolved auth context (§1.5); null if family-less. */
  role: Role | null;
  deviceId: string;
  body: unknown;
}

export interface PatchDeviceSettingsResult {
  device: DeviceView;
  features: Features;
}

export async function patchDeviceSettings(
  input: PatchDeviceSettingsInput,
  deps: PatchDeviceSettingsDeps,
): Promise<PatchDeviceSettingsResult> {
  // Own partition first (covers the common case: own device, any role, family or not).
  let device = await deps.deviceRepo.getDevice(input.uid, input.deviceId);
  if (!device && input.familyId) {
    // Not the caller's own device — only reachable at all if a parent is editing another
    // family member's device, so fan out across the family's per-owner partitions.
    const members = await deps.familyRepo.listMembers(input.familyId);
    device = await findDeviceInFamily(members, input.deviceId, deps.deviceRepo);
  }
  if (!device) {
    throw new AppError("DEVICE_NOT_FOUND", "unknown deviceId");
  }

  const patch = parseOrThrow(patchDeviceSettingsRequestSchema, input.body);

  // staleNudgeEnabled is the owner's own notification preference (001 §4.3, 011 §4.4): owner
  // only, in EVERY role — a parent on another member's device is forbidden, whole request.
  if (patch.staleNudgeEnabled !== undefined && device.ownerUserId !== input.uid) {
    throw new AppError("AUTH_FORBIDDEN", "staleNudgeEnabled can only be changed by the device owner");
  }

  if (input.familyId) {
    const isParent = input.role === "parent";
    if (!isParent) {
      const isOwner = device.ownerUserId === input.uid;
      if (!isOwner) {
        throw new AppError("AUTH_FORBIDDEN", "caller is neither a parent nor the device owner");
      }
      const restrictedFieldRequested =
        patch.syncIntervalMinutes !== undefined || patch.trackingEnabled !== undefined || patch.deviceName !== undefined;
      if (restrictedFieldRequested) {
        throw new AppError("AUTH_FORBIDDEN", "a non-parent owner may only update pushToken and staleNudgeEnabled");
      }
    }
  }
  // Family-less owner: any field of their own device is allowed (§4.3) — the device is
  // guaranteed to be the caller's own, since it was looked up in their own partition.

  let features: Features;
  if (input.familyId) {
    const entitlements = await deps.entitlementsRepo.get(input.familyId);
    if (!entitlements) {
      throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
    }
    features = getFeatures(entitlements.subscriptionStatus);
  } else {
    // Family-less callers have no Entitlements row — implicit free (001 §9, 002 §2.6).
    features = getFeatures("free");
  }

  // §1.4/§9 — plan floor on top of the schema's fixed allowed set. Both PLAN_MATRIX tiers
  // currently share the same 5-minute floor (plan.ts), so this branch is unreachable today;
  // kept per §9's "every limit enforcement point reads features, never a literal" so a future
  // paid tier with a higher floor is enforced with zero code changes here.
  if (
    patch.syncIntervalMinutes !== undefined &&
    patch.syncIntervalMinutes < features.limits.minSyncIntervalMinutes
  ) {
    throw new AppError("LIMIT_EXCEEDED", "syncIntervalMinutes is below the plan floor", {
      limit: "minSyncIntervalMinutes",
    });
  }

  const settingsChanged =
    (patch.syncIntervalMinutes !== undefined && patch.syncIntervalMinutes !== device.syncIntervalMinutes) ||
    (patch.trackingEnabled !== undefined && patch.trackingEnabled !== device.trackingEnabled);

  const updated: DeviceRecord = {
    ...device,
    syncIntervalMinutes: patch.syncIntervalMinutes ?? device.syncIntervalMinutes,
    trackingEnabled: patch.trackingEnabled ?? device.trackingEnabled,
    deviceName: patch.deviceName ?? device.deviceName,
    pushToken: patch.pushToken ?? device.pushToken,
    staleNudgeEnabled: patch.staleNudgeEnabled ?? device.staleNudgeEnabled,
  };
  // Write back into the DEVICE OWNER's own partition (002 §2.4) — not necessarily the
  // caller's, since a parent may be editing another member's device.
  // Update-only: a concurrent DELETE /devices/{id} (001 §4.4) after our read must not be
  // undone by this write resurrecting the row.
  const written = await deps.deviceRepo.replaceExistingDevice(updated.ownerUserId, updated);
  if (!written) {
    throw new AppError("DEVICE_NOT_FOUND", "device was removed mid-request");
  }

  if (settingsChanged && updated.pushToken && !updated.pushInvalid) {
    try {
      const outcome = await deps.pushSender.send({
        token: updated.pushToken,
        type: "SETTINGS_CHANGED",
        data: {
          type: "SETTINGS_CHANGED",
          syncIntervalMinutes: String(updated.syncIntervalMinutes),
          trackingEnabled: String(updated.trackingEnabled),
        },
      });
      if (outcome === "invalidToken") {
        await deps.deviceRepo.replaceExistingDevice(updated.ownerUserId, { ...updated, pushInvalid: true });
      }
    } catch {
      // Best-effort accelerator (§4.3) — never fails the request (§10 PUSH_DELIVERY_FAILED note).
    }
  }

  return { device: toDeviceView(updated), features };
}
