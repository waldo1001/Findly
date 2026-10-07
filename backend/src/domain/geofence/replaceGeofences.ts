// specs/001 §7.2 — replace geofence config (parent-only). Pure domain logic: no
// Azure/Google imports. Full-document replace with optimistic concurrency: If-Match is
// REQUIRED ("0" sentinel for the very first write); a stale/mismatched value maps storage's
// 412 to 409 GEOFENCE_VERSION_CONFLICT (002 §3.4). Side effect on success: GEOFENCE_CONFIG_CHANGED
// push (§8.4) to every family device (best-effort, silent on failure — §10). Devices are
// keyed by ownerUserId, not familyId (002 §2.4, B8 re-key): the fan-out is the family
// roster plus one small per-member Devices partition scan each
// (src/domain/family/deviceFanout.ts).

import { AppError } from "../../http/errors";
import { parseOrThrow, replaceGeofencesRequestSchema } from "../../http/validate";
import type { DeviceRepo, EntitlementsRepo, FamilyRepo, Role } from "../../ports/repositories";
import type { GeofenceConfigDocument, GeofenceConfigRepo, GeofenceEntry } from "../../ports/geofenceConfig";
import type { PushSender } from "../../ports/pushSender";
import { listDevicesForMembers } from "../family/deviceFanout";
import { getFeatures, type Features } from "../plan";

export interface ReplaceGeofencesDeps {
  geofenceConfigRepo: GeofenceConfigRepo;
  deviceRepo: DeviceRepo;
  familyRepo: FamilyRepo;
  entitlementsRepo: EntitlementsRepo;
  pushSender: PushSender;
}

export interface ReplaceGeofencesInput {
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  /** The caller's role from the resolved auth context (§1.5); only "parent" may replace (§1.6). */
  role: Role | null;
  /** The request's If-Match header value, or null when absent — REQUIRED (§7.2). */
  ifMatch: string | null;
  body: unknown;
}

export interface ReplaceGeofencesResult {
  version: number;
  geofences: GeofenceEntry[];
  etag: string;
  features: Features;
}

/**
 * specs/001 §7.2 — duplicate geofenceId slugs across the replacement array. Bracket-notation
 * field paths mirror validate.ts's array-index convention (e.g. "geofences[1].geofenceId"),
 * flagging every entry after the first occurrence of a given slug.
 */
function findDuplicateSlugFields(geofences: { geofenceId: string }[]): string[] {
  const seen = new Set<string>();
  const fields: string[] = [];
  geofences.forEach((g, index) => {
    if (seen.has(g.geofenceId)) {
      fields.push(`geofences[${index}].geofenceId`);
    } else {
      seen.add(g.geofenceId);
    }
  });
  return fields;
}

export async function replaceGeofences(
  input: ReplaceGeofencesInput,
  deps: ReplaceGeofencesDeps,
): Promise<ReplaceGeofencesResult> {
  if (!input.familyId) {
    throw new AppError("FAMILY_NOT_FOUND", "caller has no family");
  }
  const familyId = input.familyId;

  if (input.role !== "parent") {
    throw new AppError("AUTH_FORBIDDEN", "only a parent may replace the geofence config");
  }

  if (!input.ifMatch) {
    throw new AppError("VALIDATION_FAILED", "If-Match header is required", { fields: ["If-Match"] });
  }
  const ifMatch = input.ifMatch;

  const entitlements = await deps.entitlementsRepo.get(familyId);
  if (!entitlements) {
    throw new AppError("INTERNAL_ERROR", "family has no entitlements record");
  }
  const features = getFeatures(entitlements.subscriptionStatus);

  const body = parseOrThrow(replaceGeofencesRequestSchema, input.body);

  if (body.geofences.length > features.limits.maxGeofences) {
    throw new AppError("LIMIT_EXCEEDED", "geofences exceed the plan's maxGeofences limit", {
      limit: "maxGeofences",
    });
  }

  const duplicateFields = findDuplicateSlugFields(body.geofences);
  if (duplicateFields.length > 0) {
    throw new AppError("VALIDATION_FAILED", "geofenceId slugs must be unique within the config", {
      fields: duplicateFields,
    });
  }

  const current = await deps.geofenceConfigRepo.get(familyId);
  const nextDocument: GeofenceConfigDocument = {
    version: current.config.version + 1,
    geofences: body.geofences,
  };

  const outcome = await deps.geofenceConfigRepo.replace(familyId, nextDocument, ifMatch);
  if (outcome.outcome === "conflict") {
    throw new AppError("GEOFENCE_VERSION_CONFLICT", "If-Match does not match the current config ETag", {
      currentEtag: outcome.currentEtag,
    });
  }

  const members = await deps.familyRepo.listMembers(familyId);
  const devices = await listDevicesForMembers(members, deps.deviceRepo);
  for (const device of devices) {
    if (!device.pushToken || device.pushInvalid) continue;
    try {
      const sendOutcome = await deps.pushSender.send({
        token: device.pushToken,
        type: "GEOFENCE_CONFIG_CHANGED",
        data: { type: "GEOFENCE_CONFIG_CHANGED", etag: outcome.etag },
      });
      if (sendOutcome === "invalidToken") {
        // Write back into the DEVICE OWNER's own partition (002 §2.4).
        await deps.deviceRepo.replaceExistingDevice(device.ownerUserId, { ...device, pushInvalid: true });
      }
    } catch {
      // Fan-out is silent/best-effort (§10 PUSH_DELIVERY_FAILED note) — never fails the request.
    }
  }

  return { version: nextDocument.version, geofences: nextDocument.geofences, etag: outcome.etag, features };
}
