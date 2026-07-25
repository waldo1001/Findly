// specs/001 — zod request-body schemas + the shared parse-or-throw helper.
// VALIDATION_FAILED's `details.fields` (§10) is populated from zod issue paths.

import { z } from "zod";
import { AppError } from "./errors";

// specs/001 §5.1/§10 — array indices use BRACKET notation (e.g. "fixes[3].recordedAt"),
// not dot-joined ("fixes.3.recordedAt"): a numeric segment appends as `[N]` with no
// leading dot; a named segment appends as `.name`, except when it's the first segment.
function formatFieldPath(path: (string | number)[]): string {
  if (path.length === 0) return "(root)";
  let formatted = "";
  path.forEach((segment, index) => {
    if (typeof segment === "number") {
      formatted += `[${segment}]`;
    } else if (index === 0) {
      formatted += segment;
    } else {
      formatted += `.${segment}`;
    }
  });
  return formatted;
}

export function parseOrThrow<S extends z.ZodTypeAny>(schema: S, input: unknown): z.infer<S> {
  const result = schema.safeParse(input);
  if (!result.success) {
    const fields = result.error.issues.map((issue) => formatFieldPath(issue.path as (string | number)[]));
    throw new AppError("VALIDATION_FAILED", "request failed schema validation", { fields });
  }
  return result.data;
}

// specs/001 §3.1 — familyName 1-50 chars; displayName 1-30 chars.
export const createFamilyRequestSchema = z.object({
  familyName: z.string().min(1).max(50),
  displayName: z.string().min(1).max(30),
});
export type CreateFamilyRequest = z.infer<typeof createFamilyRequestSchema>;

// specs/001 §4.1 — deviceId/platform/model/appVersion required; rest optional.
export const registerDeviceRequestSchema = z.object({
  deviceId: z.string().uuid(),
  platform: z.enum(["android", "ios"]),
  model: z.string().min(1).max(60),
  appVersion: z.string().min(1),
  pushToken: z.string().min(1).optional(),
  locationPushToken: z.string().min(1).optional(),
  deviceName: z.string().min(1).max(40).optional(),
});
export type RegisterDeviceRequest = z.infer<typeof registerDeviceRequestSchema>;

// specs/001 §4.3 — the {deviceId} path param. deviceId is always a client-generated UUIDv4
// (§1.4), so `.uuid()` alone already rejects every Table Storage RowKey-forbidden character
// — no extra regex needed (contrast memberUserIdParamSchema, whose userId is free-form).
export const deviceIdParamSchema = z.object({
  deviceId: z.string().uuid(),
});
export type DeviceIdParam = z.infer<typeof deviceIdParamSchema>;

// specs/001 §1.4 — syncIntervalMinutes' exact allowed set; anything else is VALIDATION_FAILED
// here. The separate `>= features.limits.minSyncIntervalMinutes` plan-floor check (§9) needs
// `features`, so it lives in the domain (patchDeviceSettings.ts), not this schema.
const SYNC_INTERVAL_MINUTES_OPTIONS = new Set([5, 10, 15, 30, 60, 120, 1440]);

// specs/001 §4.3 — update device settings: at least one field required.
export const patchDeviceSettingsRequestSchema = z
  .object({
    syncIntervalMinutes: z
      .number()
      .refine((value) => SYNC_INTERVAL_MINUTES_OPTIONS.has(value))
      .optional(),
    trackingEnabled: z.boolean().optional(),
    deviceName: z.string().min(1).max(40).optional(),
    pushToken: z.string().min(1).optional(),
  })
  .refine(
    (data) =>
      data.syncIntervalMinutes !== undefined ||
      data.trackingEnabled !== undefined ||
      data.deviceName !== undefined ||
      data.pushToken !== undefined,
  );
export type PatchDeviceSettingsRequest = z.infer<typeof patchDeviceSettingsRequestSchema>;

// specs/001 §5.1 / §1.4 — one location fix. `fixes` array length (1-100) is enforced by
// the domain (LOCATION_BATCH_TOO_LARGE / VALIDATION_FAILED are distinct codes, §10), not here.
export const locationFixSchema = z.object({
  fixId: z.string().uuid(),
  recordedAt: z.string().datetime(),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
  accuracyM: z.number().min(0).max(10000),
  altitudeM: z.number().optional(),
  speedMps: z.number().min(0).optional(),
  bearingDeg: z.number().min(0).lt(360).optional(),
  batteryPct: z.number().int().min(0).max(100),
  source: z.enum(["periodic", "locate", "geofence", "manual"]),
});
export type LocationFixRequest = z.infer<typeof locationFixSchema>;

// specs/001 §5.1 — batchId + at least one fix (empty batch -> VALIDATION_FAILED here;
// the >100 cap is a separate pre-check in the domain, see above).
export const reportLocationsRequestSchema = z.object({
  batchId: z.string().uuid(),
  fixes: z.array(locationFixSchema).min(1),
});
export type ReportLocationsRequest = z.infer<typeof reportLocationsRequestSchema>;

// specs/001 §3.3 — role of the invitee; emailHint optional, valid email if present.
export const createInviteRequestSchema = z.object({
  role: z.enum(["parent", "member"]),
  emailHint: z.string().email().optional(),
});
export type CreateInviteRequest = z.infer<typeof createInviteRequestSchema>;

// specs/001 §3.4 — inviteCode canonicalized by the domain (uppercase, no hyphen) after
// this schema only checks presence; displayName 1-30 chars (same rule as §3.1).
export const acceptInviteRequestSchema = z.object({
  inviteCode: z.string().min(1),
  displayName: z.string().min(1).max(30),
});
export type AcceptInviteRequest = z.infer<typeof acceptInviteRequestSchema>;

// specs/001 §3.5 — at least one of role/displayName required.
export const updateMemberRequestSchema = z
  .object({
    role: z.enum(["parent", "member"]).optional(),
    displayName: z.string().min(1).max(30).optional(),
  })
  .refine((data) => data.role !== undefined || data.displayName !== undefined, {
    message: "at least one field (role or displayName) is required",
  });
export type UpdateMemberRequest = z.infer<typeof updateMemberRequestSchema>;

// specs/001 §3.5/§3.6 — the {userId} path param. Table Storage forbids `/ \ # ?` and
// control characters in PartitionKey/RowKey (002 §2); rejecting those here surfaces a
// clean 400 VALIDATION_FAILED instead of a raw SDK RestError leaking out as 500.
// \p{Cc} = Unicode "control character" category (requires the `u` flag); `/` and `\`
// are escaped because they're also forbidden Table Storage key characters. Uses `*`
// (not `+`) so an empty string fails ONLY `.min(1)` below, not this regex too — a single
// VALIDATION_FAILED issue per problem, instead of a duplicate "userId" field entry.
const ALLOWED_TABLE_KEY_CHARS = /^[^\p{Cc}/\\#?]*$/u;

export const memberUserIdParamSchema = z.object({
  userId: z
    .string()
    .min(1)
    .max(128)
    .regex(ALLOWED_TABLE_KEY_CHARS, "userId contains characters forbidden in a Table Storage key"),
});
export type MemberUserIdParam = z.infer<typeof memberUserIdParamSchema>;

// specs/001 §12.3/§12.4/§12.5/§12.7/§12.9 — the {groupId} path param. groupId is always
// server-generated (grp_ + 20 [A-Za-z0-9], §1.4), but the literal path segment is
// caller-controlled, so validate defensively like memberUserIdParamSchema above.
export const groupIdParamSchema = z.object({
  groupId: z
    .string()
    .min(1)
    .max(128)
    .regex(ALLOWED_TABLE_KEY_CHARS, "groupId contains characters forbidden in a Table Storage key"),
});
export type GroupIdParam = z.infer<typeof groupIdParamSchema>;

// specs/001 §12.1 — create group. name 1-50 chars; expiryPolicy is the 005 §2.1 enum;
// endsAt is a datetime string here only — the >= now+1h / <= maxGroupDurationDays window
// needs `now` + `features`, so it's a domain-level check (createGroup.ts), same idiom as
// minSyncIntervalMinutes' plan floor. displayName is optional here too: "required only when
// bootstrapping a profile" needs the profile lookup, also domain-level (001 §12.1/§1.5.3).
export const createGroupRequestSchema = z.object({
  name: z.string().min(1).max(50),
  endsAt: z.string().datetime(),
  expiryPolicy: z.enum(["delete", "grace", "archive"]),
  displayName: z.string().min(1).max(30).optional(),
});
export type CreateGroupRequest = z.infer<typeof createGroupRequestSchema>;

// specs/001 §12.6 — join group. code is canonicalized by the domain (uppercase, no hyphen,
// same as inviteCode) AFTER this schema validates its raw shape — 16 chars comfortably
// covers the 8-char canonical form plus the "XXXX-XXXX" hyphenated display form, and the
// same Table-Storage-key character gate as groupIdParamSchema/memberUserIdParamSchema
// applies here too: the normalized code is used verbatim as a GroupCodes PartitionKey
// (002 §2.11), so an unvalidated value could otherwise reach the table adapter and surface
// a raw SDK RestError as 500 instead of a clean 400 (docs/security-review-checklist.md).
// displayName optional (same bootstrap rule as createGroupRequestSchema above).
export const joinGroupRequestSchema = z.object({
  code: z
    .string()
    .min(1)
    .max(16)
    .regex(ALLOWED_TABLE_KEY_CHARS, "code contains characters forbidden in a Table Storage key"),
  displayName: z.string().min(1).max(30).optional(),
});
export type JoinGroupRequest = z.infer<typeof joinGroupRequestSchema>;

// specs/001 §12.4 — patch group (owner): at least one of name/endsAt required. The
// >now / <=maxGroupDurationDays window (and the archived/expired 410 gate) needs `now` +
// `features`, so — same idiom as createGroupRequestSchema's endsAt — it's a domain-level
// check (patchGroup.ts), not expressible here.
export const patchGroupRequestSchema = z
  .object({
    name: z.string().min(1).max(50).optional(),
    endsAt: z.string().datetime().optional(),
  })
  .refine((data) => data.name !== undefined || data.endsAt !== undefined, {
    message: "at least one field (name or endsAt) is required",
  });
export type PatchGroupRequest = z.infer<typeof patchGroupRequestSchema>;

// specs/001 §6.1 — create locate request: exactly one of targetUserId | targetDeviceId.
// No custom .refine() message: parseOrThrow only ever surfaces `issue.path` (see
// formatFieldPath above), never `issue.message`, so a message here would be dead weight.
export const createLocateRequestRequestSchema = z
  .object({
    targetUserId: z.string().min(1).optional(),
    targetDeviceId: z.string().uuid().optional(),
  })
  .refine(
    (body) => (body.targetUserId !== undefined ? 1 : 0) + (body.targetDeviceId !== undefined ? 1 : 0) === 1,
  );
export type CreateLocateRequestRequest = z.infer<typeof createLocateRequestRequestSchema>;

// specs/001 §6.3 — fulfill locate request: one fix, same shape as §5.1, but `source` MUST be "locate".
export const fulfillLocateRequestRequestSchema = z.object({
  fix: locationFixSchema.extend({ source: z.literal("locate") }),
});
export type FulfillLocateRequestRequest = z.infer<typeof fulfillLocateRequestRequestSchema>;

// specs/001 §5.3 `GET /locations/history` query params. `from`/`to` are required non-empty
// strings here only — real calendar-date validity, the 31-day span cap, and the
// historyDays retention window are semantic checks owned entirely by
// src/domain/history/dateRange.ts (mutation-tested there; keeping a second date-shape
// regex here would only be a redundant, unobservable-by-tests gate).
export const locationHistoryQuerySchema = z.object({
  userId: z.string().min(1),
  deviceId: z.string().min(1).optional(),
  from: z.string().min(1),
  to: z.string().min(1),
  limit: z.coerce.number().int().min(1).max(500).optional(),
  cursor: z.string().min(1).optional(),
});
export type LocationHistoryQuery = z.infer<typeof locationHistoryQuerySchema>;

// specs/001 §7.4 `GET /geofence-events` query params (the history READ; the POST at the
// same route is owned by B5, registered as a separate app.http handler).
export const geofenceEventHistoryQuerySchema = z.object({
  from: z.string().min(1),
  to: z.string().min(1),
  userId: z.string().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(500).optional(),
  cursor: z.string().min(1).optional(),
});
export type GeofenceEventHistoryQuery = z.infer<typeof geofenceEventHistoryQuerySchema>;

// specs/001 §1.4 — geofenceId is a client-chosen slug `gf_[a-z0-9-]{1,30}`, unique within
// the family config (uniqueness is a domain-level check, not expressible per-field here).
const GEOFENCE_ID_REGEX = /^gf_[a-z0-9-]{1,30}$/;

// specs/001 §7.2 — one geofence entry of the PUT /geofences full-document replace body.
// radiusM 100-5000 (platform accuracy floor / sanity cap); name 1-50; icon free string <=30.
export const geofenceEntryRequestSchema = z.object({
  geofenceId: z.string().regex(GEOFENCE_ID_REGEX),
  name: z.string().min(1).max(50),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
  radiusM: z.number().min(100).max(5000),
  icon: z.string().max(30),
  notifyOnEnter: z.boolean(),
  notifyOnExit: z.boolean(),
});
export type GeofenceEntryRequest = z.infer<typeof geofenceEntryRequestSchema>;

// specs/001 §7.2 — the geofences array only; version/ETag are server-managed. maxGeofences
// (a plan limit) and geofenceId-uniqueness are domain-level checks (both need context this
// schema doesn't have), not enforced here.
export const replaceGeofencesRequestSchema = z.object({
  geofences: z.array(geofenceEntryRequestSchema),
});
export type ReplaceGeofencesRequest = z.infer<typeof replaceGeofencesRequestSchema>;

// specs/001 §7.3 — one reported geofence transition. eventId/geofenceId format match the
// same conventions as §1.4; transition is "enter" | "exit".
export const geofenceEventRequestSchema = z.object({
  eventId: z.string().uuid(),
  geofenceId: z.string().regex(GEOFENCE_ID_REGEX),
  transition: z.enum(["enter", "exit"]),
  recordedAt: z.string().datetime(),
});
export type GeofenceEventRequest = z.infer<typeof geofenceEventRequestSchema>;

// specs/001 §7.3 — batch of 1-20 events. Unlike §5.1's fixes batch, BOTH the empty case and
// the over-limit case map to the same VALIDATION_FAILED code (no distinct "too large" code
// exists for this endpoint, §10), so a single zod min/max suffices without a domain pre-check.
export const reportGeofenceEventsRequestSchema = z.object({
  events: z.array(geofenceEventRequestSchema).min(1).max(20),
});
export type ReportGeofenceEventsRequest = z.infer<typeof reportGeofenceEventsRequestSchema>;

// specs/001 §13.1 `GET /export` query params. `userId` is optional (defaults to the caller,
// 008 §3) and, like memberUserIdParamSchema, gets the Table-Storage-key character gate
// because a validated value reaches DeviceRepo/LastKnownRepo/etc. lookups keyed by it.
export const exportQuerySchema = z.object({
  userId: z
    .string()
    .min(1)
    .max(128)
    .regex(ALLOWED_TABLE_KEY_CHARS, "userId contains characters forbidden in a Table Storage key")
    .optional(),
});
export type ExportQuery = z.infer<typeof exportQuerySchema>;
