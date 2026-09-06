// specs/001 §6.2 — poll locate request. Pure domain logic: no Azure/Google imports.

import { AppError } from "../../http/errors";
import type { Clock } from "../../ports/support";
import type { EntitlementsRepo, LocateRequestRepo, LocateRequestStatus } from "../../ports/repositories";
import { getFeatures, type Features } from "../plan";

export interface PollLocateRequestDeps {
  locateRequestRepo: LocateRequestRepo;
  entitlementsRepo: EntitlementsRepo;
  clock: Clock;
}

export interface PollLocateRequestInput {
  uid: string;
  /** The caller's familyId from the resolved auth context (§1.5), null if no profile. */
  familyId: string | null;
  requestId: string;
}

/** §5.1 fix wire shape plus the target deviceId (§6.2). */
export interface LocateRequestFix {
  fixId: string;
  recordedAt: string;
  lat: number;
  lon: number;
  accuracyM: number;
  altitudeM?: number;
  speedMps?: number;
  bearingDeg?: number;
  batteryPct: number;
  source: "locate";
  deviceId: string;
}

export interface PollLocateRequestResult {
  requestId: string;
  status: LocateRequestStatus;
  createdAt: string;
  expiresAt: string;
  /** Server receive time of the accepted fulfil (§6.3), null until fulfilled. */
  fulfilledAt: string | null;
  /** True when fulfilled after expiresAt (§6.3 grace window, amended 2026-09-06). */
  late: boolean;
  fix: LocateRequestFix | null;
  features: Features;
}

export async function pollLocateRequest(
  input: PollLocateRequestInput,
  deps: PollLocateRequestDeps,
): Promise<PollLocateRequestResult> {
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

  if (record.requestedBy !== input.uid) {
    throw new AppError("AUTH_FORBIDDEN", "only the requester may poll this locate request");
  }

  const now = deps.clock.now();
  let status = record.status;
  if (status === "pending" && now.getTime() > new Date(record.expiresAt).getTime()) {
    status = "expired";
    await deps.locateRequestRepo.update(familyId, record.requestId, { status: "expired" });
  }

  const fix: LocateRequestFix | null =
    status === "fulfilled" && record.fixJson
      ? { ...(JSON.parse(record.fixJson) as Omit<LocateRequestFix, "deviceId">), deviceId: record.targetDeviceId }
      : null;

  return {
    requestId: record.requestId,
    status,
    createdAt: record.createdAt,
    expiresAt: record.expiresAt,
    fulfilledAt: record.fulfilledAt ?? null,
    late: record.late ?? false,
    fix,
    features,
  };
}
