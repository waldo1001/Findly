// specs/001 §4.1 — register/update own device. Pure domain logic: no Azure/Google imports.
// Devices are stored per-owner (002 §2.4, B8 re-key): registration does not require a
// family (§1.5 step 4). The partition is ALWAYS the caller's own uid — family membership
// no longer changes the partition key at all.
//
// The deviceIdInUse conflict check (§1.4/§4.1) is family-wide when the caller has a
// family: §4.2's open-family device listing lets every member read every other member's
// deviceId, so without an explicit family-wide check a member could deliberately
// re-register a sibling's known deviceId under their own account and hijack a later
// by-deviceId lookup (a parent's PATCH /devices/{deviceId}, a locate request's
// targetDeviceId). A family-less caller's check stays scoped to their own partition —
// family-less deviceIds are never exposed to any other user, so no equivalent risk exists.

import { AppError } from "../../http/errors";
import { parseOrThrow, registerDeviceRequestSchema } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type { DeviceRecord, DeviceRepo, EntitlementsRepo, FamilyRepo } from "../../ports/repositories";
import { findDeviceInFamily } from "../family/deviceFanout";
import { getFeatures, type Features } from "../plan";
import { toDeviceView, type DeviceView } from "./deviceView";

export interface RegisterDeviceDeps {
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface RegisterDeviceInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  body: unknown;
}

export interface RegisterDeviceResult {
  /** true = 201 (new registration), false = 200 (upsert) — the function layer picks the status. */
  created: boolean;
  device: DeviceView;
  features: Features;
}

export async function registerDevice(
  input: RegisterDeviceInput,
  deps: RegisterDeviceDeps,
): Promise<RegisterDeviceResult> {
  // The device partition is always the caller's own uid (002 §2.4 — "the partition is the
  // owner"), family member or not.
  const ownerUserId = input.uid;

  const body = parseOrThrow(registerDeviceRequestSchema, input.body);

  const existing = await deps.deviceRepo.getDevice(ownerUserId, body.deviceId);
  if (existing && existing.ownerUserId !== input.uid) {
    // Data-integrity defense-in-depth: the caller's own partition holding a row whose
    // ownerUserId disagrees shouldn't structurally happen (every write keys by its own
    // ownerUserId), but is checked anyway.
    throw new AppError("VALIDATION_FAILED", "deviceId is registered to a different user", {
      reason: "deviceIdInUse",
    });
  }

  // §1.4/§4.1 — family-wide deviceIdInUse check: reject if ANY other member of the same
  // family already holds this deviceId (not just the caller's own partition), closing the
  // visibility-driven collision risk opened by §4.2's open-family device listing.
  if (!existing && input.familyId) {
    const members = await deps.familyRepo.listMembers(input.familyId);
    const conflict = await findDeviceInFamily(members, body.deviceId, deps.deviceRepo);
    if (conflict && conflict.ownerUserId !== input.uid) {
      throw new AppError("VALIDATION_FAILED", "deviceId is registered to a different user", {
        reason: "deviceIdInUse",
      });
    }
  }

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

  const now = deps.clock.now().toISOString();

  if (!existing) {
    const count = await deps.deviceRepo.countDevices(ownerUserId);
    if (count >= features.limits.maxDevices) {
      throw new AppError("LIMIT_EXCEEDED", "device cap reached", { limit: "maxDevices" });
    }

    const record: DeviceRecord = {
      deviceId: body.deviceId,
      ownerUserId: input.uid,
      platform: body.platform,
      model: body.model,
      appVersion: body.appVersion,
      deviceName: body.deviceName ?? body.model,
      pushToken: body.pushToken,
      locationPushToken: body.locationPushToken,
      pushInvalid: false,
      syncIntervalMinutes: 15,
      trackingEnabled: true,
      registeredAt: now,
      lastSeenAt: now,
      staleNudgeEnabled: true,
    };
    await deps.deviceRepo.putDevice(ownerUserId, record);
    return { created: true, device: toDeviceView(record), features };
  }

  const updated: DeviceRecord = {
    ...existing,
    platform: body.platform,
    model: body.model,
    appVersion: body.appVersion,
    // Fresh tokens replace the stored one; an omitted token preserves what's on file
    // (clients resend on every launch/refresh per §4.1, but a plain appVersion update
    // MUST NOT silently wipe out a previously-registered valid token).
    pushToken: body.pushToken ?? existing.pushToken,
    locationPushToken: body.locationPushToken ?? existing.locationPushToken,
    // §8.5 token hygiene: a genuinely FRESH pushToken (different from what's on file)
    // clears a previously-set pushInvalid — the flag reflects "is the CURRENT token
    // known-bad", not "was some PAST token ever bad". Re-registering with the SAME
    // already-invalid token must NOT clear it (that would let a permanently-broken
    // token launder itself clean just by resending), and omitting pushToken entirely
    // leaves the flag untouched too.
    pushInvalid:
      body.pushToken !== undefined && body.pushToken !== existing.pushToken
        ? false
        : existing.pushInvalid,
    lastSeenAt: now,
    // Parent-managed settings are NEVER reset by an upsert (§4.1):
    syncIntervalMinutes: existing.syncIntervalMinutes,
    trackingEnabled: existing.trackingEnabled,
    deviceName: existing.deviceName,
    // Owner-managed (001 §4.1) and nudger-written fields survive an upsert untouched:
    staleNudgeEnabled: existing.staleNudgeEnabled,
    lastNudgedAt: existing.lastNudgedAt,
  };
  await deps.deviceRepo.putDevice(ownerUserId, updated);
  return { created: false, device: toDeviceView(updated), features };
}
