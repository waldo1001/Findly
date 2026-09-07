// specs/001 §7.3 — report geofence events. Pure domain logic: no Azure/Google imports.
// Sent by the device that natively detected the transition. Mirrors reportLocations.ts's
// §1.2 device-ownership + pause pattern. Every accepted event is ALWAYS appended to history
// (with geofenceName/lat/lon/radiusM frozen from the current config, or null when the
// geofenceId is unknown/stale) regardless of notification flags; the GEOFENCE_EVENT push
// (§8.2) fans out to every other family device only when the matching geofence's
// notifyOnEnter/notifyOnExit flag for this transition is true (§7.1/§8.2). Devices are
// keyed by ownerUserId, not familyId (002 §2.4, B8 re-key): the fan-out is one small
// partition scan per family member (src/domain/family/deviceFanout.ts), lazily fetched and
// cached at most once per batch, same as the pre-existing displayName caching.

import { AppError } from "../../http/errors";
import { parseOrThrow, reportGeofenceEventsRequestSchema } from "../../http/validate";
import type { Clock } from "../../ports/support";
import type {
  DeviceRecord,
  DeviceRepo,
  EntitlementsRepo,
  FamilyMember,
  FamilyRepo,
  IdempotencyRepo,
  UsageRepo,
} from "../../ports/repositories";
import type { EventLine, HistoryStore } from "../../ports/historyStore";
import type { GeofenceConfigRepo, GeofenceEntry } from "../../ports/geofenceConfig";
import type { PushSender } from "../../ports/pushSender";
import { listDevicesForMembers } from "../family/deviceFanout";
import { getFeatures, type Features } from "../plan";
import { shouldRefreshLastSeen } from "../device/lastSeenPolicy";
import { normalizeDisplayText } from "../text/normalizeDisplayText";

export interface ReportGeofenceEventsDeps {
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  geofenceConfigRepo: GeofenceConfigRepo;
  idempotencyRepo: IdempotencyRepo;
  historyStore: HistoryStore;
  usageRepo: UsageRepo;
  entitlementsRepo: EntitlementsRepo;
  pushSender: PushSender;
  clock: Clock;
}

export interface ReportGeofenceEventsInput {
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

export interface ReportGeofenceEventsResult {
  accepted: number;
  duplicates: number;
  deviceSettings: DeviceSettingsSnapshot;
  geofenceEtag: string;
  features: Features;
}

function usageDate(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function notifyFlagFor(geofence: GeofenceEntry, transition: "enter" | "exit"): boolean {
  return transition === "enter" ? geofence.notifyOnEnter : geofence.notifyOnExit;
}

/** specs/001 §8.2 — normative title template: no time in the text (server doesn't know the
 * recipient's time zone; the notification's own timestamp conveys it).
 *
 * Re-normalizes both inputs (B29 review finding 5) instead of trusting the stored values
 * as-is: this is a write-time-only fix with no migration, so a displayName/geofenceName
 * written before normalizeDisplayText existed stays hostile in storage until its owner
 * writes again. normalizeDisplayText is pure and idempotent, so applying it again here to
 * an already-clean value is a no-op — this only matters for pre-existing data. */
function titleFor(displayName: string, geofenceName: string, transition: "enter" | "exit"): string {
  const name = normalizeDisplayText(displayName);
  const geofence = normalizeDisplayText(geofenceName);
  return transition === "enter" ? `${name} arrived at ${geofence}` : `${name} left ${geofence}`;
}

function resolveDisplayName(uid: string, members: FamilyMember[]): string {
  const member = members.find((m) => m.userId === uid);
  return member?.displayName ?? uid;
}

export async function reportGeofenceEvents(
  input: ReportGeofenceEventsInput,
  deps: ReportGeofenceEventsDeps,
): Promise<ReportGeofenceEventsResult> {
  if (!input.familyId) {
    throw new AppError("FAMILY_NOT_FOUND", "caller has no family");
  }
  const familyId = input.familyId;

  const entitlements = await deps.entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  const features = getFeatures(entitlements.subscriptionStatus);

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

  const now = deps.clock.now();

  // specs/001 §4.2 (amended 2026-09-06) — every device-originated call refreshes
  // lastSeenAt, write-skipped to at most once per minute (002 §2.4). touchLastSeen is a
  // timestamp-only merge (never a full-row replace of this stale-by-construction snapshot)
  // so a concurrent PATCH /devices/{id} (§4.3) or re-registration (§4.1) can't be clobbered.
  if (shouldRefreshLastSeen(device.lastSeenAt, now)) {
    await deps.deviceRepo.touchLastSeen(input.uid, deviceId, now.toISOString());
  }

  const deviceSettings: DeviceSettingsSnapshot = {
    syncIntervalMinutes: device.syncIntervalMinutes,
    trackingEnabled: device.trackingEnabled,
  };

  if (!device.trackingEnabled) {
    throw new AppError("TRACKING_PAUSED", "device tracking is paused", { deviceSettings });
  }

  const body = parseOrThrow(reportGeofenceEventsRequestSchema, input.body);

  const receivedAt = now.toISOString();
  const date = usageDate(now);

  const { config, etag: geofenceEtag } = await deps.geofenceConfigRepo.get(familyId);
  const geofenceById = new Map(config.geofences.map((g) => [g.geofenceId, g] as const));

  let accepted = 0;
  let duplicates = 0;
  let members: FamilyMember[] | null = null;
  let displayName: string | null = null;
  let familyDevices: DeviceRecord[] | null = null;

  for (const event of body.events) {
    const inserted = await deps.idempotencyRepo.tryInsertEventMarker(deviceId, event.eventId, receivedAt);
    if (!inserted) {
      duplicates++;
      continue;
    }
    accepted++;

    const matched = geofenceById.get(event.geofenceId) ?? null;
    const eventLine: EventLine = {
      eventId: event.eventId,
      userId: input.uid,
      deviceId,
      geofenceId: event.geofenceId,
      geofenceName: matched ? matched.name : null,
      lat: matched ? matched.lat : null,
      lon: matched ? matched.lon : null,
      radiusM: matched ? matched.radiusM : null,
      transition: event.transition,
      recordedAt: event.recordedAt,
      receivedAt,
    };
    await deps.historyStore.appendEvent(familyId, eventLine);

    if (matched && notifyFlagFor(matched, event.transition)) {
      if (members === null) {
        members = await deps.familyRepo.listMembers(familyId);
      }
      if (displayName === null) {
        displayName = resolveDisplayName(input.uid, members);
      }
      if (familyDevices === null) {
        familyDevices = await listDevicesForMembers(members, deps.deviceRepo);
      }
      const title = titleFor(displayName, matched.name, event.transition);
      for (const target of familyDevices) {
        if (target.deviceId === deviceId) continue; // never notify the reporting device (§8.2)
        if (!target.pushToken || target.pushInvalid) continue;
        try {
          const outcome = await deps.pushSender.send({
            token: target.pushToken,
            type: "GEOFENCE_EVENT",
            notificationTitle: title,
            data: {
              type: "GEOFENCE_EVENT",
              userId: input.uid,
              displayName,
              geofenceId: event.geofenceId,
              geofenceName: matched.name,
              transition: event.transition,
              recordedAt: event.recordedAt,
            },
          });
          if (outcome === "invalidToken") {
            // Write back into the DEVICE OWNER's own partition (002 §2.4).
            await deps.deviceRepo.putDevice(target.ownerUserId, { ...target, pushInvalid: true });
          }
        } catch {
          // Fan-out is silent/best-effort (§10 PUSH_DELIVERY_FAILED note) — never fails the request.
        }
      }
    }
  }

  if (accepted > 0) {
    await deps.usageRepo.increment(familyId, "geofenceEvents", date, accepted);
  }

  return { accepted, duplicates, deviceSettings, geofenceEtag, features };
}
