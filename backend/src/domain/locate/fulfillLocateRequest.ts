// specs/001 §6.3 — fulfill locate request. Pure domain logic: no Azure/Google imports.
// Called by the TARGET device. TRACKING_PAUSED intentionally never applies here (§6.3) —
// a paused device MAY still fulfill, so device.trackingEnabled is deliberately never
// inspected below. But §1.2's device-ownership precondition still applies to every
// device-originated call: X-Device-Id MUST match a device registered to the calling user
// (else 404 DEVICE_NOT_FOUND) — mirrors reportLocations.ts's ownership check — BEFORE the
// separate §6.3 business rule that the device must equal the request's actual target
// (else 403 AUTH_FORBIDDEN). Skipping the ownership check would let any family member
// forge another member's location by supplying a sibling's known deviceId.

import { AppError } from "../../http/errors";
import { fulfillLocateRequestRequestSchema, parseOrThrow, type LocationFixRequest } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type {
  DeviceRepo,
  EntitlementsRepo,
  IdempotencyRepo,
  LastKnownRecord,
  LastKnownRepo,
  LocateRequestRepo,
  UsageRepo,
} from "../../ports/repositories";
import type { FixLine, HistoryStore } from "../../ports/historyStore";
import { getFeatures, type Features } from "../plan";
import { shouldRefreshLastSeen } from "../device/lastSeenPolicy";

// specs/001 §6.3 (amended 2026-09-06) — a fulfil received within this many ms after
// expiresAt is still accepted (late:true) instead of throwing LOCATE_REQUEST_EXPIRED.
const GRACE_MS = 10 * 60 * 1000;

export interface FulfillLocateRequestDeps {
  deviceRepo: DeviceRepo;
  locateRequestRepo: LocateRequestRepo;
  lastKnownRepo: LastKnownRepo;
  historyStore: HistoryStore;
  idempotencyRepo: IdempotencyRepo;
  usageRepo: UsageRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface FulfillLocateRequestInput {
  uid: string;
  /** The X-Device-Id header (§1.2), null if absent. */
  deviceId: string | null;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  requestId: string;
  body: unknown;
}

export interface FulfillLocateRequestResult {
  status: "fulfilled";
  /** True when this fulfil (or the original one, for an idempotent/history-only replay)
   * was accepted after expiresAt (§6.3 grace window, amended 2026-09-06). */
  late: boolean;
  features: Features;
}

function usageDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function buildFixLine(fix: LocationFixRequest, receivedAt: string): FixLine {
  return {
    fixId: fix.fixId,
    recordedAt: fix.recordedAt,
    receivedAt,
    lat: fix.lat,
    lon: fix.lon,
    accuracyM: fix.accuracyM,
    ...(fix.altitudeM !== undefined ? { altitudeM: fix.altitudeM } : {}),
    ...(fix.speedMps !== undefined ? { speedMps: fix.speedMps } : {}),
    ...(fix.bearingDeg !== undefined ? { bearingDeg: fix.bearingDeg } : {}),
    batteryPct: fix.batteryPct,
    source: fix.source,
  };
}

export async function fulfillLocateRequest(
  input: FulfillLocateRequestInput,
  deps: FulfillLocateRequestDeps,
): Promise<FulfillLocateRequestResult> {
  if (!input.familyId) {
    throw new AppError("FAMILY_NOT_FOUND", "caller has no family");
  }
  const familyId = input.familyId;

  const entitlements = await deps.entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  const features = getFeatures(entitlements.subscriptionStatus);

  const record = await deps.locateRequestRepo.get(familyId, input.requestId);
  if (!record) {
    throw new AppError("LOCATE_REQUEST_NOT_FOUND", "unknown requestId");
  }

  // specs/001 §1.2 — device-ownership precondition (mirrors reportLocations.ts): the
  // header is required, and MUST resolve to a device actually registered to this caller.
  // Devices are keyed by ownerUserId (002 §2.4, B8 re-key): a point read in the caller's
  // OWN partition — no family fan-out needed, since a device can only ever live in its
  // owner's partition.
  if (!input.deviceId) {
    throw new AppError("AUTH_FORBIDDEN", "X-Device-Id header is required to fulfill a locate request");
  }
  const callerDeviceId = input.deviceId;
  const device = await deps.deviceRepo.getDevice(input.uid, callerDeviceId);
  if (!device || device.ownerUserId !== input.uid) {
    throw new AppError("DEVICE_NOT_FOUND", "X-Device-Id is not registered to the calling user");
  }

  // specs/001 §6.3 — separately, the fulfilling device must be the request's actual target.
  if (callerDeviceId !== record.targetDeviceId) {
    throw new AppError("AUTH_FORBIDDEN", "X-Device-Id does not match the locate request's target device");
  }

  const body = parseOrThrow(fulfillLocateRequestRequestSchema, input.body);

  const now = deps.clock.now();
  const receivedAt = now.toISOString();
  const date = usageDate(now);
  const nowMs = now.getTime();
  const expiresAtMs = new Date(record.expiresAt).getTime();
  const late = nowMs > expiresAtMs;
  const withinGrace = nowMs <= expiresAtMs + GRACE_MS;

  // specs/001 §4.2/§6.3 (amended 2026-09-06) — every device-originated call refreshes
  // lastSeenAt, write-skipped to at most once per minute (002 §2.4).
  if (shouldRefreshLastSeen(device.lastSeenAt, now)) {
    await deps.deviceRepo.putDevice(device.ownerUserId, { ...device, lastSeenAt: now.toISOString() });
  }

  const inserted = await deps.idempotencyRepo.tryInsertFixMarker(record.targetDeviceId, body.fix.fixId, receivedAt);
  if (inserted) {
    const lastKnownCandidate: LastKnownRecord = {
      deviceId: record.targetDeviceId,
      lat: body.fix.lat,
      lon: body.fix.lon,
      accuracyM: body.fix.accuracyM,
      ...(body.fix.altitudeM !== undefined ? { altitudeM: body.fix.altitudeM } : {}),
      ...(body.fix.speedMps !== undefined ? { speedMps: body.fix.speedMps } : {}),
      ...(body.fix.bearingDeg !== undefined ? { bearingDeg: body.fix.bearingDeg } : {}),
      batteryPct: body.fix.batteryPct,
      recordedAt: body.fix.recordedAt,
      receivedAt,
      source: body.fix.source,
    };
    // LastKnown is keyed by ownerUserId (002 §2.5, B8 re-key) — the target's own
    // partition; record.targetUserId is already known (callerDeviceId === targetDeviceId
    // and the ownership check above proved input.uid owns it, so they're the same value).
    await deps.lastKnownRepo.upsertIfNewer(record.targetUserId, lastKnownCandidate);
    await deps.historyStore.appendFix(
      familyId,
      record.targetUserId,
      record.targetDeviceId,
      buildFixLine(body.fix, receivedAt),
    );
    await deps.usageRepo.increment(familyId, "fixes", date);
  }

  // specs/001 §6.3 (amended 2026-09-06) — a second fulfil for an already-fulfilled request
  // is idempotent on fixId: same fixId replays the same result; a DIFFERENT fixId is
  // stored as history/last-known above, but does NOT replace fixJson/late/fulfilledAt on
  // the request row itself. Either way, no throw — the request already reached its
  // terminal fulfilled state, regardless of how much time has passed since.
  if (record.status === "fulfilled") {
    return { status: "fulfilled", late: record.late ?? false, features };
  }

  if (!withinGrace) {
    if (record.status === "pending") {
      await deps.locateRequestRepo.update(familyId, record.requestId, { status: "expired" });
    }
    throw new AppError("LOCATE_REQUEST_EXPIRED", "locate request expired before it was fulfilled");
  }

  const fixJson = JSON.stringify(toStoredFix(body.fix));
  await deps.locateRequestRepo.update(familyId, record.requestId, {
    status: "fulfilled",
    fixJson,
    fulfilledAt: receivedAt,
    late,
  });

  return { status: "fulfilled", late, features };
}

/**
 * Builds the plain object later JSON.stringify'd into LocateRequestRecord.fixJson (§6.2's
 * poll-response fix). Exported so unit tests can assert key-presence on the raw object
 * directly — JSON.stringify silently drops `undefined`-valued keys, which would otherwise
 * make a mutant that always includes an absent optional key (as `undefined`) look
 * equivalent once serialized, even though the pre-serialization shape did change.
 */
export function toStoredFix(fix: LocationFixRequest): Record<string, unknown> {
  return {
    fixId: fix.fixId,
    recordedAt: fix.recordedAt,
    lat: fix.lat,
    lon: fix.lon,
    accuracyM: fix.accuracyM,
    ...(fix.altitudeM !== undefined ? { altitudeM: fix.altitudeM } : {}),
    ...(fix.speedMps !== undefined ? { speedMps: fix.speedMps } : {}),
    ...(fix.bearingDeg !== undefined ? { bearingDeg: fix.bearingDeg } : {}),
    batteryPct: fix.batteryPct,
    source: fix.source,
  };
}
