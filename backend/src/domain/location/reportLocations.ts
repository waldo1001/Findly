// specs/001 §5.1 — report locations (batch). Pure domain logic: no Azure/Google imports.
// Unlike §5.2/§6/§7, §5.1 explicitly works WITHOUT a family (001 §1.5 step 4): Devices/
// LastKnown are keyed by ownerUserId (002 §2.4/§2.5, B8 re-key), so the §1.2 ownership
// check and the last-known upsert are always a point read/write in the caller's OWN
// partition, family or not. Only the per-fix HISTORY append is gated on having a family
// (005 §3's "group participation never creates durable location history"): a family-less
// user's fixes update last-known only. geofenceEtag is the family-scoped config's ETag when
// a family exists, else the fixed "0" sentinel (no config to sync, geofences are family-only).
//
// Group fan-out (001 §5.1 side effect, 002 §2.12, B11): independently of the family
// last-known write above, the batch's newest fix is also upserted into every one of the
// reporter's ACTIVE groups (005 §2.2) — position-only, only-newer (src/domain/group/
// groupLocationFanout.ts). Groups don't require a family, so this runs for family-less
// callers too.

import { AppError } from "../../http/errors";
import { parseOrThrow, reportLocationsRequestSchema, type LocationFixRequest } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type {
  DeviceRepo,
  EntitlementsRepo,
  FamilyRepo,
  GroupLastKnownRepo,
  GroupRepo,
  IdempotencyRepo,
  LastKnownRecord,
  LastKnownRepo,
  UsageRepo,
  UserRepo,
} from "../../ports/repositories";
import type { FixLine, HistoryStore } from "../../ports/historyStore";
import type { GeofenceConfigRepo } from "../../ports/geofenceConfig";
import { getFeatures, type Features } from "../plan";
import { fanOutLocationToActiveGroups } from "../group/groupLocationFanout";

const MAX_BATCH_SIZE = 100;
const CLOCK_SKEW_TOLERANCE_MS = 5 * 60 * 1000;

export interface ReportLocationsDeps {
  deviceRepo: DeviceRepo;
  lastKnownRepo: LastKnownRepo;
  idempotencyRepo: IdempotencyRepo;
  historyStore: HistoryStore;
  usageRepo: UsageRepo;
  geofenceConfigRepo: GeofenceConfigRepo;
  entitlementsRepo: EntitlementsRepo;
  userRepo: UserRepo;
  /** Write-time family-existence guard (002 §4.2, closes the in-flight erasure race): a
   * point read this task reuses from an existing port, not a new one. */
  familyRepo: FamilyRepo;
  groupRepo: GroupRepo;
  groupLastKnownRepo: GroupLastKnownRepo;
  clock: Clock;
}

export interface ReportLocationsInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  /** The X-Device-Id header (§1.2), null if absent. */
  deviceId: string | null;
  body: unknown;
}

export interface DeviceSettingsSnapshot {
  syncIntervalMinutes: number;
  trackingEnabled: boolean;
}

export interface ReportLocationsResult {
  accepted: number;
  duplicates: number;
  lastKnownUpdated: boolean;
  deviceSettings: DeviceSettingsSnapshot;
  geofenceEtag: string;
  features: Features;
}

function usageDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function fixesRawArray(body: unknown): unknown[] | null {
  if (typeof body !== "object" || body === null) return null;
  const fixes = (body as Record<string, unknown>).fixes;
  return Array.isArray(fixes) ? fixes : null;
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

function newestFix(fixes: LocationFixRequest[]): LocationFixRequest {
  return fixes.reduce((newest, current) =>
    new Date(current.recordedAt).getTime() > new Date(newest.recordedAt).getTime() ? current : newest,
  );
}

export async function reportLocations(
  input: ReportLocationsInput,
  deps: ReportLocationsDeps,
): Promise<ReportLocationsResult> {
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

  if (!input.deviceId) {
    throw new AppError("DEVICE_NOT_FOUND", "X-Device-Id header is required");
  }
  const deviceId = input.deviceId;

  // §1.2 ownership check: a point read in the caller's own partition (002 §2.4) — no
  // family fan-out needed, since a device can only ever live in its owner's partition.
  const device = await deps.deviceRepo.getDevice(input.uid, deviceId);
  if (!device || device.ownerUserId !== input.uid) {
    throw new AppError("DEVICE_NOT_FOUND", "X-Device-Id is not registered to the calling user");
  }

  const deviceSettings: DeviceSettingsSnapshot = {
    syncIntervalMinutes: device.syncIntervalMinutes,
    trackingEnabled: device.trackingEnabled,
  };

  if (!device.trackingEnabled) {
    throw new AppError("TRACKING_PAUSED", "device tracking is paused", { deviceSettings });
  }

  const rawFixes = fixesRawArray(input.body);
  if (rawFixes !== null && rawFixes.length > MAX_BATCH_SIZE) {
    throw new AppError("LOCATION_BATCH_TOO_LARGE", "fixes batch exceeds the maximum of 100 entries", {
      max: MAX_BATCH_SIZE,
    });
  }

  const body = parseOrThrow(reportLocationsRequestSchema, input.body);

  const now = deps.clock.now();
  const maxAllowedMs = now.getTime() + CLOCK_SKEW_TOLERANCE_MS;
  const skewFields: string[] = [];
  body.fixes.forEach((fix, index) => {
    if (new Date(fix.recordedAt).getTime() > maxAllowedMs) {
      skewFields.push(`fixes[${index}].recordedAt`);
    }
  });
  if (skewFields.length > 0) {
    throw new AppError("VALIDATION_FAILED", "fix recordedAt is too far in the future (clock skew)", {
      fields: skewFields,
    });
  }

  const receivedAt = now.toISOString();
  // Geofences are family-scoped (§7.1) — a family-less caller has no config to sync.
  const geofenceEtag = input.familyId ? await deps.geofenceConfigRepo.getEtag(input.familyId) : "0";

  const inserted = await deps.idempotencyRepo.tryInsertBatchMarker(deviceId, body.batchId, {
    receivedAt,
    fixCount: body.fixes.length,
  });

  if (!inserted) {
    return {
      accepted: 0,
      duplicates: body.fixes.length,
      lastKnownUpdated: false,
      deviceSettings,
      geofenceEtag,
      features,
    };
  }

  const newest = newestFix(body.fixes);
  const lastKnownCandidate: LastKnownRecord = {
    deviceId,
    lat: newest.lat,
    lon: newest.lon,
    accuracyM: newest.accuracyM,
    ...(newest.altitudeM !== undefined ? { altitudeM: newest.altitudeM } : {}),
    ...(newest.speedMps !== undefined ? { speedMps: newest.speedMps } : {}),
    ...(newest.bearingDeg !== undefined ? { bearingDeg: newest.bearingDeg } : {}),
    batteryPct: newest.batteryPct,
    recordedAt: newest.recordedAt,
    receivedAt,
    source: newest.source,
  };
  const lastKnownUpdated = await deps.lastKnownRepo.upsertIfNewer(input.uid, lastKnownCandidate);

  // Group fan-out (001 §5.1 side effect, 002 §2.12): active-only, position-only, only-newer
  // — independent of lastKnownUpdated above (a group's stored position is its own row).
  await fanOutLocationToActiveGroups(
    input.uid,
    {
      lat: newest.lat,
      lon: newest.lon,
      accuracyM: newest.accuracyM,
      recordedAt: newest.recordedAt,
      syncIntervalMinutes: device.syncIntervalMinutes,
    },
    receivedAt,
    features.limits.groupGraceDays,
    now,
    { userRepo: deps.userRepo, groupRepo: deps.groupRepo, groupLastKnownRepo: deps.groupLastKnownRepo },
  );

  // Write-time family-existence guard (002 §4.2, security review-gate fix): input.familyId
  // is a snapshot taken by the auth layer BEFORE this function ran (001 §1.5). A concurrent
  // DELETE /families/me (001 §13.3) can complete while this batch is in flight; because the
  // history append is create-if-not-exists, trusting the stale snapshot could silently
  // recreate location coordinates under a family that was just erased — and since privacy
  // deletion is one-shot with no sweeper (008 §1.2), that remnant would be permanent.
  // Re-verify immediately before the family-scoped writes below (reusing the existing
  // FamilyRepo.getFamilyMeta point read — no new port); if the family is gone, degrade to
  // family-less handling for the REST of this request only (last-known and group fan-out
  // above are unaffected — they're already done and were never family-scoped).
  const familyIdForWrite =
    input.familyId && (await deps.familyRepo.getFamilyMeta(input.familyId)) ? input.familyId : null;

  // History gate (005 §3, 001 §5.1): only appended when the caller has a family that still
  // exists at write time — a family-less (or just-erased) caller's fixes update last-known
  // (and group positions) only.
  if (familyIdForWrite) {
    for (const fix of body.fixes) {
      await deps.historyStore.appendFix(familyIdForWrite, input.uid, deviceId, buildFixLine(fix, receivedAt));
    }
  }

  // Usage (002 §2.9) stays familyId-keyed only while that family still exists at write
  // time; otherwise it degrades to the caller's own uid partition, same as a family-less
  // caller — unrelated to the Devices/LastKnown re-key.
  const usagePartition = familyIdForWrite ?? input.uid;
  const date = usageDate(now);
  await deps.usageRepo.increment(usagePartition, "locationBatches", date);
  await deps.usageRepo.increment(usagePartition, "fixes", date, body.fixes.length);

  return {
    accepted: body.fixes.length,
    duplicates: 0,
    lastKnownUpdated,
    deviceSettings,
    geofenceEtag,
    features,
  };
}
