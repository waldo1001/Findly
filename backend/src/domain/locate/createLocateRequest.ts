// specs/001 §6.1 — create locate request. Pure domain logic: no Azure/Google imports.
// Devices/LastKnown are keyed by ownerUserId, not familyId (002 §2.4/§2.5, B8 re-key):
// target resolution fans out across the family's per-owner partitions
// (src/domain/family/deviceFanout.ts) instead of a single shared family scan.

import { AppError } from "../../http/errors";
import { createLocateRequestRequestSchema, parseOrThrow } from "../../http/validate";
import type { Clock, IdGenerator } from "../../ports/support";
import type {
  DeviceRecord,
  DeviceRepo,
  EntitlementsRepo,
  FamilyMember,
  FamilyRepo,
  LastKnownRecord,
  LastKnownRepo,
  LocateRequestRecord,
  LocateRequestRepo,
  LocateRequestStatus,
  UsageRepo,
} from "../../ports/repositories";
import type { PushSender } from "../../ports/pushSender";
import { findDeviceInFamily, listDevicesForMembers } from "../family/deviceFanout";
import { getFeatures, type Features } from "../plan";
import { EMPTY_DISPLAY_NAME_FALLBACK, normalizeDisplayTextOrFallback } from "../text/normalizeDisplayText";

const REQUEST_ID_LENGTH = 20;
const EXPIRY_MS = 180 * 1000; // now + 180s (§6.1, amended 2026-09-06 — was 60s)

export interface CreateLocateRequestDeps {
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  lastKnownRepo: LastKnownRepo;
  locateRequestRepo: LocateRequestRepo;
  usageRepo: UsageRepo;
  entitlementsRepo: EntitlementsRepo;
  pushSender: PushSender;
  idGenerator: IdGenerator;
  clock: Clock;
}

export interface CreateLocateRequestInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  body: unknown;
}

export interface LastKnownAnswer {
  deviceId: string;
  lat: number;
  lon: number;
  accuracyM: number;
  recordedAt: string;
}

export interface CreateLocateRequestResult {
  /** true = 201 (new request created), false = 200 (coalesced with an existing pending request). */
  created: boolean;
  requestId: string;
  status: LocateRequestStatus;
  targetUserId: string;
  targetDeviceId: string;
  createdAt: string;
  expiresAt: string;
  lastKnown: LastKnownAnswer | null;
  features: Features;
}

function usageDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function hasValidToken(device: DeviceRecord): boolean {
  return !!device.pushToken && !device.pushInvalid;
}

function mostRecentlySeen(devices: DeviceRecord[]): DeviceRecord {
  return devices.reduce((best, current) =>
    new Date(current.lastSeenAt).getTime() > new Date(best.lastSeenAt).getTime() ? current : best,
  );
}

/** specs/001 §6.1 ordered target resolution. Fans out across the family's per-owner
 * Devices partitions (`members` is the caller's family roster) — a target device may
 * belong to any family member, not just the caller. */
async function resolveTarget(
  body: { targetUserId?: string; targetDeviceId?: string },
  members: FamilyMember[],
  deviceRepo: DeviceRepo,
): Promise<{ targetUserId: string; device: DeviceRecord }> {
  if (body.targetDeviceId) {
    const device = await findDeviceInFamily(members, body.targetDeviceId, deviceRepo);
    if (!device) {
      throw new AppError("DEVICE_NOT_FOUND", "unknown targetDeviceId");
    }
    if (!device.trackingEnabled) {
      throw new AppError("TRACKING_PAUSED", "target device tracking is paused");
    }
    return { targetUserId: device.ownerUserId, device };
  }

  const targetUserId = body.targetUserId as string;
  const familyDevices = await listDevicesForMembers(members, deviceRepo);
  const candidates = familyDevices.filter((d) => d.ownerUserId === targetUserId);
  if (candidates.length === 0) {
    throw new AppError("DEVICE_NOT_FOUND", "target user has no registered devices");
  }
  const unpaused = candidates.filter((d) => d.trackingEnabled);
  if (unpaused.length === 0) {
    throw new AppError("TRACKING_PAUSED", "all of the target user's devices are paused");
  }
  const withValidToken = unpaused.filter(hasValidToken);
  const pool = withValidToken.length > 0 ? withValidToken : unpaused;
  return { targetUserId, device: mostRecentlySeen(pool) };
}

function resolveRequesterDisplayName(uid: string, members: FamilyMember[]): string {
  const requester = members.find((member) => member.userId === uid);
  return requester?.displayName ?? uid;
}

/** specs/001 §8.1 (amended 2026-09-06, 000 §O8) — normative, server-composed, English in v1.
 * The single place this template is authored: passed through PushMessage.notificationTitle
 * (src/ports/pushSender.ts) exactly as reportGeofenceEvents.ts does for §8.2, so the pure
 * FCM body builder (src/domain/push/fcmMessageBodies.ts) just plugs the field in rather than
 * knowing the wording itself.
 *
 * Re-normalizes requestedByName (B29 review finding 5) instead of trusting the stored value
 * as-is: this is a write-time-only fix with no migration, so a displayName written before
 * normalizeDisplayText existed stays hostile in storage until its owner writes again.
 * normalizeDisplayText is pure and idempotent, so applying it again here to an already-clean
 * value is a no-op — this only matters for pre-existing data.
 *
 * Falls back to the §1.4 placeholder (B29 re-review, residual fix) when requestedByName
 * normalizes to the empty string — a stored value consisting ENTIRELY of forbidden
 * characters — instead of emitting `" is locating you"` with a leading space and no name. */
function buildLocateRequestTitle(requestedByName: string): string {
  return `${normalizeDisplayTextOrFallback(requestedByName, EMPTY_DISPLAY_NAME_FALLBACK)} is locating you`;
}

function toLastKnownAnswer(deviceId: string, record: LastKnownRecord | null): LastKnownAnswer | null {
  if (!record) return null;
  return { deviceId, lat: record.lat, lon: record.lon, accuracyM: record.accuracyM, recordedAt: record.recordedAt };
}

export async function createLocateRequest(
  input: CreateLocateRequestInput,
  deps: CreateLocateRequestDeps,
): Promise<CreateLocateRequestResult> {
  if (!input.familyId) {
    throw new AppError("FAMILY_NOT_FOUND", "caller has no family");
  }
  const familyId = input.familyId;

  const entitlements = await deps.entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  const features = getFeatures(entitlements.subscriptionStatus);

  const body = parseOrThrow(createLocateRequestRequestSchema, input.body);
  const members = await deps.familyRepo.listMembers(familyId);
  const { targetUserId, device } = await resolveTarget(body, members, deps.deviceRepo);
  const targetDeviceId = device.deviceId;

  const now = deps.clock.now();
  const date = usageDate(now);
  // LastKnown is keyed by ownerUserId (002 §2.5, B8 re-key) — the target's own partition,
  // known once resolveTarget identifies the device's owner.
  const lastKnownRecord = await deps.lastKnownRepo.get(targetUserId, targetDeviceId);
  const lastKnown = toLastKnownAnswer(targetDeviceId, lastKnownRecord);

  const pending = await deps.locateRequestRepo.listPendingByTargetDevice(familyId, targetDeviceId);
  if (pending.length > 0) {
    const existing = pending[0]!;
    return {
      created: false,
      requestId: existing.requestId,
      status: existing.status,
      targetUserId,
      targetDeviceId,
      createdAt: existing.createdAt,
      expiresAt: existing.expiresAt,
      lastKnown,
      features,
    };
  }

  const usedToday = await deps.usageRepo.get(familyId, "locateRequests", date);
  if (usedToday >= features.limits.locateRequestsPerDay) {
    throw new AppError("LIMIT_EXCEEDED", "daily locate-request quota reached", {
      limit: "locateRequestsPerDay",
    });
  }

  const requestId = `lr_${deps.idGenerator.next(REQUEST_ID_LENGTH)}`;
  const createdAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + EXPIRY_MS).toISOString();

  let status: LocateRequestStatus = "pending";
  if (hasValidToken(device)) {
    const requestedByName = resolveRequesterDisplayName(input.uid, members);
    try {
      const outcome = await deps.pushSender.send({
        token: device.pushToken as string,
        type: "LOCATE_REQUEST",
        notificationTitle: buildLocateRequestTitle(requestedByName),
        data: { type: "LOCATE_REQUEST", requestId, requestedByName, expiresAt },
      });
      if (outcome === "invalidToken") {
        status = "pushFailed";
        // Write back into the DEVICE OWNER's own partition (002 §2.4) — the target, not
        // necessarily the requester.
        await deps.deviceRepo.putDevice(device.ownerUserId, { ...device, pushInvalid: true });
      } else if (outcome === "error") {
        // specs/001 §6.1/§6.2 (amended 2026-09-06) — a non-throwing "error" outcome (every
        // non-ok, non-token-rejection FCM response, including an FCM 5xx — see
        // src/adapters/push/fcmV1Sender.ts) is a transport-level failure exactly like a
        // thrown one below: create the request as pushFailed WITHOUT marking the device
        // pushInvalid — the token itself is not known bad, only the send attempt failed.
        status = "pushFailed";
      }
    } catch {
      // specs/001 §6.1 (amended 2026-09-06) — a THROWN transport-level failure (OAuth
      // exchange failure, a missing/malformed FCM_SERVICE_ACCOUNT_JSON, or a rejected
      // fetch — the only cases fcmV1Sender.ts actually throws for; an FCM 5xx resolves as
      // the non-throwing "error" outcome handled above, it does NOT throw) MUST NOT fail
      // the request: create it as pushFailed exactly like an invalid token, but WITHOUT
      // marking the device pushInvalid — the token itself is not known bad, only the send
      // attempt failed. The requester still gets their last-known answer instead of a 500.
      status = "pushFailed";
    }
  } else {
    status = "pushFailed";
  }

  const record: LocateRequestRecord = {
    requestId,
    familyId,
    targetUserId,
    targetDeviceId,
    requestedBy: input.uid,
    status,
    createdAt,
    expiresAt,
  };
  await deps.locateRequestRepo.create(record);

  await deps.usageRepo.increment(familyId, "locateRequests", date);

  return {
    created: true,
    requestId,
    status,
    targetUserId,
    targetDeviceId,
    createdAt,
    expiresAt,
    lastKnown,
    features,
  };
}
