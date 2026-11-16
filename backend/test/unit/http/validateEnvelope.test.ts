// specs/001 §10 (VALIDATION_FAILED) / §5.1 - characterisation of the exact envelope that
// parseOrThrow (src/http/validate.ts) produces for EVERY request schema's failure path.
//
// B40 guard: these tests were written GREEN against zod 3 and must stay green UNCHANGED
// across the zod 3 -> 4 migration (zod 4 changed issue shape, paths, messages and several
// string-format validators). They are ADD-ONLY: never loosen or edit one to make a new zod
// pass; a failure here means the wire contract moved and the migration code must be fixed
// (or, if a documented wire shape would change, the spec owner decides).
//
// What is pinned: error `code`, the constant `message`, `details` containing exactly one
// key `fields`, the field-path strings (bracket notation for array indexes, dotted names
// for nested objects, "(root)" for a root-level failure), their ORDER (schema key order,
// then array index order) and their MULTIPLICITY (one entry per zod issue, not deduped).

import { describe, expect, it } from "vitest";
import { z } from "zod";
import {
  acceptInviteRequestSchema,
  createFamilyRequestSchema,
  createGroupRequestSchema,
  createInviteRequestSchema,
  createLocateRequestRequestSchema,
  deviceIdParamSchema,
  exportQuerySchema,
  fulfillLocateRequestRequestSchema,
  geofenceEntryRequestSchema,
  geofenceEventHistoryQuerySchema,
  geofenceEventRequestSchema,
  groupIdParamSchema,
  joinGroupRequestSchema,
  locationFixSchema,
  locationHistoryQuerySchema,
  memberUserIdParamSchema,
  parseOrThrow,
  patchDeviceSettingsRequestSchema,
  patchGroupRequestSchema,
  registerDeviceRequestSchema,
  replaceGeofencesRequestSchema,
  reportGeofenceEventsRequestSchema,
  reportLocationsRequestSchema,
  updateMemberRequestSchema,
} from "../../../src/http/validate";
import { AppError } from "../../../src/http/errors";
import { fail } from "../../../src/http/envelope";

const UUID_A = "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b";
const UUID_B = "4f1a3b0d-7c2e-4f9a-8b3c-8d6e5f4a3b2c";

/** Runs parseOrThrow and returns either {ok: data} or the AppError (never throws). */
function run<S extends z.ZodTypeAny>(
  schema: S,
  input: unknown,
): { ok: true; data: z.infer<S> } | { ok: false; error: AppError } {
  try {
    return { ok: true, data: parseOrThrow(schema, input) };
  } catch (error) {
    if (error instanceof AppError) return { ok: false, error };
    throw error;
  }
}

/** The `details.fields` array of a failing parse; fails the test when the parse succeeds. */
function fieldsOf(schema: z.ZodTypeAny, input: unknown): string[] {
  const result = run(schema, input);
  if (result.ok) throw new Error(`expected VALIDATION_FAILED but parse succeeded: ${JSON.stringify(result.data)}`);
  return (result.error.details as { fields: string[] }).fields;
}

function accepts(schema: z.ZodTypeAny, input: unknown): boolean {
  return run(schema, input).ok;
}

function validFix(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    fixId: UUID_A,
    recordedAt: "2026-07-05T10:00:00.000Z",
    lat: 51.0543,
    lon: 3.7174,
    accuracyM: 12,
    batteryPct: 80,
    source: "periodic",
    ...overrides,
  };
}

function validGeofence(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    geofenceId: "gf_home",
    name: "Home",
    lat: 51.0543,
    lon: 3.7174,
    radiusM: 150,
    icon: "home",
    notifyOnEnter: true,
    notifyOnExit: true,
    ...overrides,
  };
}

function validDevice(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { deviceId: UUID_A, platform: "android", model: "Pixel 8", appVersion: "1.0.0", ...overrides };
}

describe("parseOrThrow envelope shape (001 §10)", () => {
  it("throws an AppError VALIDATION_FAILED (HTTP 400) with the constant message and details {fields} only", () => {
    const result = run(createFamilyRequestSchema, {});

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBeInstanceOf(AppError);
    expect(result.error.code).toBe("VALIDATION_FAILED");
    expect(result.error.httpStatus).toBe(400);
    expect(result.error.message).toBe("request failed schema validation");
    expect(result.error.details).toEqual({ fields: ["familyName", "displayName"] });
    expect(Object.keys(result.error.details ?? {})).toEqual(["fields"]);
  });

  it("serializes into the 001 §1.3 error envelope with no zod text anywhere in the body", () => {
    const result = run(createFamilyRequestSchema, { familyName: 5, displayName: 7 });
    if (result.ok) throw new Error("expected failure");

    const envelope = fail(result.error, "req-1");

    expect(envelope).toEqual({
      error: {
        code: "VALIDATION_FAILED",
        message: "request failed schema validation",
        details: { fields: ["familyName", "displayName"] },
        requestId: "req-1",
      },
    });
    const wire = JSON.stringify(envelope);
    expect(wire).not.toMatch(/zod|expected|received|Invalid input|Required|invalid_type/i);
  });

  it("returns the parsed value (not the raw input) on success", () => {
    const result = run(createFamilyRequestSchema, { familyName: "Wauters", displayName: "  Eric  " });

    expect(result).toEqual({ ok: true, data: { familyName: "Wauters", displayName: "Eric" } });
  });
});

describe("failure paths: root-level shape", () => {
  it.each([
    ["null", null],
    ["undefined (empty body fallback)", undefined],
    ["a string", "familyName"],
    ["a number", 42],
    ["a boolean", true],
    ["an array", []],
    ["an array of valid-looking objects", [{ familyName: "a", displayName: "b" }]],
  ])('reports ["(root)"] for a body that is %s', (_label, body) => {
    expect(fieldsOf(createFamilyRequestSchema, body)).toEqual(["(root)"]);
  });

  it("reports every required key, in schema key order, for an empty object body (the `request.json().catch(() => ({}))` fallback)", () => {
    expect(fieldsOf(registerDeviceRequestSchema, {})).toEqual(["deviceId", "platform", "model", "appVersion"]);
    expect(fieldsOf(reportLocationsRequestSchema, {})).toEqual(["batchId", "fixes"]);
    expect(fieldsOf(createGroupRequestSchema, {})).toEqual(["name", "endsAt", "expiryPolicy"]);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, {})).toEqual(["fix"]);
    expect(fieldsOf(replaceGeofencesRequestSchema, {})).toEqual(["geofences"]);
    expect(fieldsOf(reportGeofenceEventsRequestSchema, {})).toEqual(["events"]);
    expect(fieldsOf(joinGroupRequestSchema, {})).toEqual(["code"]);
    expect(fieldsOf(acceptInviteRequestSchema, {})).toEqual(["inviteCode", "displayName"]);
    expect(fieldsOf(createInviteRequestSchema, {})).toEqual(["role"]);
  });

  it("reports root-level (object) refinements as (root) for an empty object", () => {
    expect(fieldsOf(patchDeviceSettingsRequestSchema, {})).toEqual(["(root)"]);
    expect(fieldsOf(updateMemberRequestSchema, {})).toEqual(["(root)"]);
    expect(fieldsOf(patchGroupRequestSchema, {})).toEqual(["(root)"]);
    expect(fieldsOf(createLocateRequestRequestSchema, {})).toEqual(["(root)"]);
  });

  it("reports (root) for a non-object body even on schemas that carry an object refinement", () => {
    expect(fieldsOf(patchDeviceSettingsRequestSchema, null)).toEqual(["(root)"]);
    expect(fieldsOf(updateMemberRequestSchema, "x")).toEqual(["(root)"]);
    expect(fieldsOf(patchGroupRequestSchema, [])).toEqual(["(root)"]);
    expect(fieldsOf(createLocateRequestRequestSchema, 1)).toEqual(["(root)"]);
  });
});

describe("failure paths: unknown / extra keys are STRIPPED, never rejected", () => {
  it("accepts and drops unknown keys on a request body", () => {
    const result = run(createFamilyRequestSchema, { familyName: "W", displayName: "E", extra: 1, nested: { a: 1 } });

    expect(result).toEqual({ ok: true, data: { familyName: "W", displayName: "E" } });
  });

  it("drops unknown keys inside array elements and nested objects", () => {
    const fixResult = run(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [validFix({ unknownField: "x" })] });
    expect(fixResult.ok && "unknownField" in (fixResult.data.fixes[0] as object)).toBe(false);
    expect(fixResult.ok).toBe(true);

    const fulfil = run(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "locate", unknownField: "x" }), junk: 1 });
    expect(fulfil.ok).toBe(true);
    if (fulfil.ok) {
      expect(Object.keys(fulfil.data)).toEqual(["fix"]);
      expect("unknownField" in fulfil.data.fix).toBe(false);
    }
  });

  it("does not let a JSON-borne __proto__ key pollute the result or the prototype", () => {
    const body: unknown = JSON.parse('{"familyName":"W","displayName":"E","__proto__":{"polluted":true}}');

    const result = run(createFamilyRequestSchema, body);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect((result.data as Record<string, unknown>).polluted).toBeUndefined();
      expect(Object.keys(result.data)).toEqual(["familyName", "displayName"]);
    }
    expect(({} as Record<string, unknown>).polluted).toBeUndefined();
  });
});

describe("failure paths: wrong type / missing / null on scalar fields", () => {
  it("reports an invalid type, a missing key and an explicit null identically (the field name)", () => {
    expect(fieldsOf(createFamilyRequestSchema, { familyName: 5, displayName: "E" })).toEqual(["familyName"]);
    expect(fieldsOf(createFamilyRequestSchema, { displayName: "E" })).toEqual(["familyName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: null, displayName: "E" })).toEqual(["familyName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: ["W"], displayName: "E" })).toEqual(["familyName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: { a: 1 }, displayName: "E" })).toEqual(["familyName"]);
  });

  it("rejects an explicit null on an optional (non-nullable) field", () => {
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ pushToken: null }))).toEqual(["pushToken"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ deviceName: null }))).toEqual(["deviceName"]);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: null, expiryPolicy: "delete", displayName: null })).toEqual([
      "displayName",
    ]);
  });

  it("accepts an explicit undefined on an optional field and treats it as absent", () => {
    expect(accepts(registerDeviceRequestSchema, validDevice({ pushToken: undefined }))).toBe(true);
  });

  it("requires the KEY of a nullable (non-optional) field but accepts null (001 §12.1)", () => {
    expect(fieldsOf(createGroupRequestSchema, { name: "G", expiryPolicy: "delete" })).toEqual(["endsAt"]);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: undefined, expiryPolicy: "delete" })).toEqual(["endsAt"]);
    expect(accepts(createGroupRequestSchema, { name: "G", endsAt: null, expiryPolicy: "delete" })).toBe(true);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: 5, expiryPolicy: "delete" })).toEqual(["endsAt"]);
  });

  it("accepts null AND absent on patchGroup's endsAt (nullable + optional)", () => {
    expect(accepts(patchGroupRequestSchema, { endsAt: null })).toBe(true);
    expect(accepts(patchGroupRequestSchema, { name: "G" })).toBe(true);
    expect(fieldsOf(patchGroupRequestSchema, { endsAt: 5 })).toEqual(["endsAt"]);
  });
});

describe("failure paths: string bounds", () => {
  it("enforces min/max length on familyName (1-50), boundaries inclusive", () => {
    expect(accepts(createFamilyRequestSchema, { familyName: "x", displayName: "E" })).toBe(true);
    expect(accepts(createFamilyRequestSchema, { familyName: "x".repeat(50), displayName: "E" })).toBe(true);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "", displayName: "E" })).toEqual(["familyName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "x".repeat(51), displayName: "E" })).toEqual(["familyName"]);
  });

  it("enforces model <= 60, deviceName <= 40 and the non-empty optional tokens", () => {
    expect(accepts(registerDeviceRequestSchema, validDevice({ model: "m".repeat(60) }))).toBe(true);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ model: "m".repeat(61) }))).toEqual(["model"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ model: "" }))).toEqual(["model"]);
    expect(accepts(registerDeviceRequestSchema, validDevice({ deviceName: "d".repeat(40) }))).toBe(true);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ deviceName: "d".repeat(41) }))).toEqual(["deviceName"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ appVersion: "" }))).toEqual(["appVersion"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ pushToken: "" }))).toEqual(["pushToken"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ locationPushToken: "" }))).toEqual(["locationPushToken"]);
  });

  it("enforces joinGroup code length 1-16 and the Table Storage key character gate", () => {
    expect(accepts(joinGroupRequestSchema, { code: "A".repeat(16) })).toBe(true);
    expect(fieldsOf(joinGroupRequestSchema, { code: "A".repeat(17) })).toEqual(["code"]);
    expect(fieldsOf(joinGroupRequestSchema, { code: "" })).toEqual(["code"]);
    expect(fieldsOf(joinGroupRequestSchema, { code: "AB/CD" })).toEqual(["code"]);
    expect(fieldsOf(joinGroupRequestSchema, { code: "AB#CD" })).toEqual(["code"]);
  });

  it("reports ONE entry per path for a string failing a single rule (no duplicate for the regex + min overlap)", () => {
    expect(fieldsOf(memberUserIdParamSchema, { userId: "" })).toEqual(["userId"]);
    expect(fieldsOf(groupIdParamSchema, { groupId: "" })).toEqual(["groupId"]);
    expect(fieldsOf(exportQuerySchema, { userId: "" })).toEqual(["userId"]);
  });

  it("reports one entry per failing RULE on the same path (two rules failing = two entries, not deduped)", () => {
    // 129 chars AND containing a forbidden "/" -> .max(128) and .regex() both fail on "userId".
    const input = { userId: "/" + "x".repeat(128) };

    expect(fieldsOf(memberUserIdParamSchema, input)).toEqual(["userId", "userId"]);
  });

  it("applies the Table Storage key gate to exportQuerySchema.userId (optional)", () => {
    expect(accepts(exportQuerySchema, {})).toBe(true);
    expect(accepts(exportQuerySchema, { userId: "u1" })).toBe(true);
    expect(fieldsOf(exportQuerySchema, { userId: "a/b" })).toEqual(["userId"]);
    expect(fieldsOf(exportQuerySchema, { userId: "x".repeat(129) })).toEqual(["userId"]);
  });

  it("treats a non-string where a string is required as a single path entry", () => {
    expect(fieldsOf(memberUserIdParamSchema, { userId: 5 })).toEqual(["userId"]);
    expect(fieldsOf(joinGroupRequestSchema, { code: 5 })).toEqual(["code"]);
  });
});

describe("failure paths: enums and literals", () => {
  it("rejects an enum mismatch, case-sensitively, on the field path", () => {
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ platform: "windows" }))).toEqual(["platform"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ platform: "Android" }))).toEqual(["platform"]);
    expect(fieldsOf(registerDeviceRequestSchema, validDevice({ platform: 1 }))).toEqual(["platform"]);
    expect(fieldsOf(createInviteRequestSchema, { role: "child" })).toEqual(["role"]);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: null, expiryPolicy: "keep" })).toEqual(["expiryPolicy"]);
    expect(fieldsOf(geofenceEventRequestSchema, { eventId: UUID_A, geofenceId: "gf_a", transition: "dwell", recordedAt: "2026-07-05T10:00:00Z" })).toEqual([
      "transition",
    ]);
  });

  it("accepts every member of each enum", () => {
    for (const platform of ["android", "ios"]) expect(accepts(registerDeviceRequestSchema, validDevice({ platform }))).toBe(true);
    for (const role of ["parent", "member"]) expect(accepts(createInviteRequestSchema, { role })).toBe(true);
    for (const expiryPolicy of ["delete", "grace", "archive"]) {
      expect(accepts(createGroupRequestSchema, { name: "G", endsAt: null, expiryPolicy })).toBe(true);
    }
    for (const source of ["periodic", "locate", "geofence", "manual"]) expect(accepts(locationFixSchema, validFix({ source }))).toBe(true);
  });

  it("pins the fulfil-locate literal: source must be exactly 'locate', and the path is nested (fix.source)", () => {
    expect(accepts(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "locate" }) })).toBe(true);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "periodic" }) })).toEqual(["fix.source"]);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "other" }) })).toEqual(["fix.source"]);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: validFix({ source: undefined }) })).toEqual(["fix.source"]);
  });
});

describe("failure paths: numeric bounds", () => {
  it("enforces lat/lon inclusive bounds", () => {
    for (const lat of [-90, 90, 0]) expect(accepts(locationFixSchema, validFix({ lat }))).toBe(true);
    for (const lat of [90.0001, -90.0001]) expect(fieldsOf(locationFixSchema, validFix({ lat }))).toEqual(["lat"]);
    for (const lon of [-180, 180]) expect(accepts(locationFixSchema, validFix({ lon }))).toBe(true);
    for (const lon of [180.0001, -180.0001]) expect(fieldsOf(locationFixSchema, validFix({ lon }))).toEqual(["lon"]);
  });

  it("enforces accuracyM 0..10000 inclusive", () => {
    for (const accuracyM of [0, 10000]) expect(accepts(locationFixSchema, validFix({ accuracyM }))).toBe(true);
    for (const accuracyM of [-0.1, 10000.1]) expect(fieldsOf(locationFixSchema, validFix({ accuracyM }))).toEqual(["accuracyM"]);
  });

  it("enforces speedMps >= 0 and bearingDeg in [0, 360) and optional altitudeM", () => {
    expect(accepts(locationFixSchema, validFix({ speedMps: 0, bearingDeg: 0, altitudeM: -50 }))).toBe(true);
    expect(accepts(locationFixSchema, validFix({ bearingDeg: 359.99 }))).toBe(true);
    expect(fieldsOf(locationFixSchema, validFix({ speedMps: -0.1 }))).toEqual(["speedMps"]);
    expect(fieldsOf(locationFixSchema, validFix({ bearingDeg: 360 }))).toEqual(["bearingDeg"]);
    expect(fieldsOf(locationFixSchema, validFix({ bearingDeg: -1 }))).toEqual(["bearingDeg"]);
    expect(fieldsOf(locationFixSchema, validFix({ altitudeM: "high" }))).toEqual(["altitudeM"]);
  });

  it("enforces batteryPct as an integer 0..100", () => {
    for (const batteryPct of [0, 100, 55]) expect(accepts(locationFixSchema, validFix({ batteryPct }))).toBe(true);
    for (const batteryPct of [-1, 101, 50.5]) expect(fieldsOf(locationFixSchema, validFix({ batteryPct }))).toEqual(["batteryPct"]);
    expect(fieldsOf(locationFixSchema, validFix({ batteryPct: undefined }))).toEqual(["batteryPct"]);
  });

  it("rejects numeric strings and null where a number is required (no coercion on body schemas)", () => {
    expect(fieldsOf(locationFixSchema, validFix({ lat: "51.05" }))).toEqual(["lat"]);
    expect(fieldsOf(locationFixSchema, validFix({ lat: null }))).toEqual(["lat"]);
    expect(fieldsOf(locationFixSchema, validFix({ lat: true }))).toEqual(["lat"]);
  });

  it("enforces geofence radiusM 100..5000 inclusive", () => {
    for (const radiusM of [100, 5000]) expect(accepts(geofenceEntryRequestSchema, validGeofence({ radiusM }))).toBe(true);
    for (const radiusM of [99.9, 5000.1]) expect(fieldsOf(geofenceEntryRequestSchema, validGeofence({ radiusM }))).toEqual(["radiusM"]);
  });

  it("restricts syncIntervalMinutes to the exact allowed set (refine on a number)", () => {
    for (const value of [5, 10, 15, 30, 60, 120, 1440]) {
      expect(accepts(patchDeviceSettingsRequestSchema, { syncIntervalMinutes: value })).toBe(true);
    }
    for (const value of [0, 1, 7, 14.5, 1441, -5]) {
      expect(fieldsOf(patchDeviceSettingsRequestSchema, { syncIntervalMinutes: value })).toEqual(["syncIntervalMinutes"]);
    }
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { syncIntervalMinutes: "15" })).toEqual(["syncIntervalMinutes"]);
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { syncIntervalMinutes: null })).toEqual(["syncIntervalMinutes"]);
  });
});

describe("failure paths: string formats (uuid, datetime, email, regex)", () => {
  it("accepts any 8-4-4-4-12 hex UUID shape (not only RFC version/variant), case-insensitively", () => {
    // Wire behaviour on zod 3: `.uuid()` is the permissive 8-4-4-4-12 hex check. Test fixtures
    // across the suite (and possibly real clients) rely on it, so it is part of the contract.
    for (const deviceId of [
      UUID_A,
      UUID_A.toUpperCase(),
      "11111111-1111-1111-1111-111111111111",
      "00000000-0000-0000-0000-000000000000",
      "ffffffff-ffff-ffff-ffff-ffffffffffff",
      "12345678-1234-1234-1234-123456789abc",
    ]) {
      expect(accepts(deviceIdParamSchema, { deviceId }), deviceId).toBe(true);
    }
  });

  it("rejects strings that are not an 8-4-4-4-12 hex UUID", () => {
    for (const deviceId of [
      "",
      "not-a-uuid",
      "3e0f2a9c6b1d4e8f9a2b7c5d4e3f2a1b",
      "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1",
      "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1bb",
      "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1g",
      " 3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b",
      "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b ",
      "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b\n",
      "{3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b}",
    ]) {
      expect(fieldsOf(deviceIdParamSchema, { deviceId }), JSON.stringify(deviceId)).toEqual(["deviceId"]);
    }
  });

  it("accepts the ISO-8601 UTC 'Z' datetimes that clients send, with arbitrary fractional precision", () => {
    for (const recordedAt of [
      "2026-07-05T10:00:00Z",
      "2026-07-05T10:00:00.000Z",
      "2026-07-05T10:00:00.1Z",
      "2026-07-05T10:00:00.123456Z",
      "2026-07-05T10:00:00.123456789Z",
      "2024-02-29T23:59:59Z",
      // zod 3.25 accepts minute precision (seconds optional); pinned because clients may rely on it.
      "2026-07-05T10:00Z",
    ]) {
      expect(accepts(locationFixSchema, validFix({ recordedAt })), recordedAt).toBe(true);
    }
  });

  it("rejects datetimes that are not strict ISO-8601 UTC 'Z' (offsets, missing Z, partial, malformed, bad calendar)", () => {
    for (const recordedAt of [
      "2026-07-05T10:00:00+02:00",
      "2026-07-05T10:00:00+00:00",
      "2026-07-05T10:00:00-05:00",
      "2026-07-05T10:00:00",
      "2026-07-05 10:00:00Z",
      "2026-07-05",
      "2026-07-05T10Z",
      "2026-07-05T10:00:00.Z",
      "2026-07-05T24:00:00Z",
      "2026-07-05T10:60:00Z",
      "2026-07-05T10:00:60Z",
      "2026-13-05T10:00:00Z",
      "2026-02-30T10:00:00Z",
      "2025-02-29T10:00:00Z",
      "2026-07-05t10:00:00z",
      "not a date",
      "",
      " 2026-07-05T10:00:00Z",
      "2026-07-05T10:00:00Z ",
      "1782000000",
    ]) {
      expect(fieldsOf(locationFixSchema, validFix({ recordedAt })), JSON.stringify(recordedAt)).toEqual(["recordedAt"]);
    }
    expect(fieldsOf(locationFixSchema, validFix({ recordedAt: 1782000000 }))).toEqual(["recordedAt"]);
    expect(fieldsOf(locationFixSchema, validFix({ recordedAt: null }))).toEqual(["recordedAt"]);
  });

  it("applies the same datetime rules to group endsAt and geofence-event recordedAt", () => {
    expect(accepts(createGroupRequestSchema, { name: "G", endsAt: "2026-07-05T10:00:00Z", expiryPolicy: "delete" })).toBe(true);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: "2026-07-05T10:00:00+01:00", expiryPolicy: "delete" })).toEqual(["endsAt"]);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: "2026-07-05", expiryPolicy: "delete" })).toEqual(["endsAt"]);
    expect(fieldsOf(patchGroupRequestSchema, { endsAt: "tomorrow" })).toEqual(["endsAt"]);
    expect(fieldsOf(geofenceEventRequestSchema, { eventId: UUID_A, geofenceId: "gf_a", transition: "enter", recordedAt: "2026-07-05T10:00:00+01:00" })).toEqual([
      "recordedAt",
    ]);
  });

  it("accepts ordinary e-mail hints and rejects malformed ones (emailHint optional)", () => {
    for (const emailHint of ["a@b.co", "first.last@example.com", "user+tag@sub.example.org", "x_y-z@ex-ample.be"]) {
      expect(accepts(createInviteRequestSchema, { role: "member", emailHint }), emailHint).toBe(true);
    }
    expect(accepts(createInviteRequestSchema, { role: "member" })).toBe(true);
    for (const emailHint of ["", "plain", "a@", "@b.com", "a b@c.com", "a@b", "a@@b.com", "a@b..com", "a@.com", "a@b.c om", 5, null]) {
      expect(fieldsOf(createInviteRequestSchema, { role: "member", emailHint }), JSON.stringify(emailHint)).toEqual(["emailHint"]);
    }
  });

  it("pins the geofenceId slug regex gf_[a-z0-9-]{1,30}, anchored both ends", () => {
    for (const geofenceId of ["gf_a", "gf_home", "gf_" + "a".repeat(30), "gf_a-b-1", "gf_-"]) {
      expect(accepts(geofenceEntryRequestSchema, validGeofence({ geofenceId })), geofenceId).toBe(true);
    }
    for (const geofenceId of ["", "gf_", "gf_" + "a".repeat(31), "GF_home", "gf_Home", "xgf_home", "gf_home!", "gf_ho me", "gf_home\n", "home", 5]) {
      expect(fieldsOf(geofenceEntryRequestSchema, validGeofence({ geofenceId })), JSON.stringify(geofenceId)).toEqual(["geofenceId"]);
    }
  });

  it("pins the geofence icon bound (<= 30, empty allowed, required)", () => {
    expect(accepts(geofenceEntryRequestSchema, validGeofence({ icon: "" }))).toBe(true);
    expect(accepts(geofenceEntryRequestSchema, validGeofence({ icon: "i".repeat(30) }))).toBe(true);
    expect(fieldsOf(geofenceEntryRequestSchema, validGeofence({ icon: "i".repeat(31) }))).toEqual(["icon"]);
    expect(fieldsOf(geofenceEntryRequestSchema, validGeofence({ icon: undefined }))).toEqual(["icon"]);
    expect(fieldsOf(geofenceEntryRequestSchema, validGeofence({ notifyOnEnter: "yes" }))).toEqual(["notifyOnEnter"]);
  });
});

describe("failure paths: transform + pipe (displayName normalization, 001 §1.4)", () => {
  it("reports a non-string displayName once on the field path", () => {
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W", displayName: 5 })).toEqual(["displayName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W", displayName: null })).toEqual(["displayName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W", displayName: {} })).toEqual(["displayName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W" })).toEqual(["displayName"]);
  });

  it("reports empty-after-normalization and over-bound-after-normalization once on the field path", () => {
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W", displayName: "" })).toEqual(["displayName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W", displayName: "   " })).toEqual(["displayName"]);
    expect(fieldsOf(createFamilyRequestSchema, { familyName: "W", displayName: "x".repeat(31) })).toEqual(["displayName"]);
  });

  it("uses the field path on every schema that embeds the normalized text (optional and required)", () => {
    expect(fieldsOf(acceptInviteRequestSchema, { inviteCode: "ABCD", displayName: "‮" })).toEqual(["displayName"]);
    expect(fieldsOf(updateMemberRequestSchema, { displayName: "" })).toEqual(["displayName"]);
    expect(fieldsOf(createGroupRequestSchema, { name: "G", endsAt: null, expiryPolicy: "delete", displayName: "x".repeat(31) })).toEqual([
      "displayName",
    ]);
    expect(fieldsOf(joinGroupRequestSchema, { code: "ABCD1234", displayName: "" })).toEqual(["displayName"]);
    expect(accepts(joinGroupRequestSchema, { code: "ABCD1234", displayName: undefined })).toBe(true);
    expect(accepts(joinGroupRequestSchema, { code: "ABCD1234" })).toBe(true);
  });

  it("nests the path under the array index for a geofence name that normalizes to empty", () => {
    expect(fieldsOf(replaceGeofencesRequestSchema, { geofences: [validGeofence(), validGeofence({ geofenceId: "gf_b", name: "‮" })] })).toEqual([
      "geofences[1].name",
    ]);
  });
});

describe("failure paths: arrays (bracket notation, indexes, ordering)", () => {
  it("uses bracket notation for an element field: fixes[3].recordedAt (001 §5.1/§10)", () => {
    const fixes = [validFix(), validFix(), validFix(), validFix({ recordedAt: "nope" })];

    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes })).toEqual(["fixes[3].recordedAt"]);
  });

  it("reports an element that is not an object at the bare index path", () => {
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [null] })).toEqual(["fixes[0]"]);
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [validFix(), "x", 5] })).toEqual(["fixes[1]", "fixes[2]"]);
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [[]] })).toEqual(["fixes[0]"]);
  });

  it("reports missing keys inside an element with the element index", () => {
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [{}] })).toEqual([
      "fixes[0].fixId",
      "fixes[0].recordedAt",
      "fixes[0].lat",
      "fixes[0].lon",
      "fixes[0].accuracyM",
      "fixes[0].batteryPct",
      "fixes[0].source",
    ]);
  });

  it("lists failures across several elements in array order, then schema key order within an element", () => {
    const fixes = [validFix({ lat: 999 }), validFix(), validFix({ source: "bogus", lon: 999 }), validFix({ batteryPct: 101 })];

    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes })).toEqual([
      "fixes[0].lat",
      "fixes[2].lon",
      "fixes[2].source",
      "fixes[3].batteryPct",
    ]);
  });

  it("uses multi-digit indexes verbatim", () => {
    const fixes = Array.from({ length: 12 }, (_unused, index) => (index === 10 ? validFix({ lat: 91 }) : validFix()));

    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes })).toEqual(["fixes[10].lat"]);
  });

  it("reports an empty fixes array and a non-array fixes at the array path (no index)", () => {
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [] })).toEqual(["fixes"]);
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: "x" })).toEqual(["fixes"]);
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: {} })).toEqual(["fixes"]);
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: UUID_B, fixes: null })).toEqual(["fixes"]);
    expect(fieldsOf(reportLocationsRequestSchema, { batchId: "bad", fixes: [] })).toEqual(["batchId", "fixes"]);
  });

  it("does NOT cap the fixes array in the schema (the 100 cap is the domain's LOCATION_BATCH_TOO_LARGE, 001 §5.1)", () => {
    const fixes = Array.from({ length: 150 }, () => validFix());

    expect(accepts(reportLocationsRequestSchema, { batchId: UUID_B, fixes })).toBe(true);
  });

  it("caps the geofence-events array at 1-20 in the schema, reporting the array path (001 §7.3)", () => {
    const event = { eventId: UUID_A, geofenceId: "gf_a", transition: "enter", recordedAt: "2026-07-05T10:00:00Z" };

    expect(accepts(reportGeofenceEventsRequestSchema, { events: [event] })).toBe(true);
    expect(accepts(reportGeofenceEventsRequestSchema, { events: Array.from({ length: 20 }, () => event) })).toBe(true);
    expect(fieldsOf(reportGeofenceEventsRequestSchema, { events: [] })).toEqual(["events"]);
    expect(fieldsOf(reportGeofenceEventsRequestSchema, { events: Array.from({ length: 21 }, () => event) })).toEqual(["events"]);
    expect(fieldsOf(reportGeofenceEventsRequestSchema, { events: Array.from({ length: 5000 }, () => event) })).toEqual(["events"]);
  });

  it("reports an element error inside the geofence-events array with its index", () => {
    const event = { eventId: UUID_A, geofenceId: "gf_a", transition: "enter", recordedAt: "2026-07-05T10:00:00Z" };

    expect(fieldsOf(reportGeofenceEventsRequestSchema, { events: [event, { ...event, transition: "dwell" }, { ...event, eventId: "x" }] })).toEqual([
      "events[1].transition",
      "events[2].eventId",
    ]);
  });

  it("accepts an empty geofences array (full-document replace may clear all) and reports element errors with index", () => {
    expect(accepts(replaceGeofencesRequestSchema, { geofences: [] })).toBe(true);
    expect(fieldsOf(replaceGeofencesRequestSchema, { geofences: [validGeofence({ radiusM: 1 }), validGeofence({ icon: 5 })] })).toEqual([
      "geofences[0].radiusM",
      "geofences[1].icon",
    ]);
    expect(fieldsOf(replaceGeofencesRequestSchema, { geofences: "x" })).toEqual(["geofences"]);
    expect(fieldsOf(replaceGeofencesRequestSchema, { geofences: [null] })).toEqual(["geofences[0]"]);
  });
});

describe("failure paths: nested objects (dotted names)", () => {
  it("joins nested object keys with a dot: fix.lat", () => {
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "locate", lat: 91 }) })).toEqual(["fix.lat"]);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "locate", recordedAt: "x", lon: 181 }) })).toEqual([
      "fix.recordedAt",
      "fix.lon",
    ]);
  });

  it("reports a non-object nested value at the nested key itself", () => {
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: "x" })).toEqual(["fix"]);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: null })).toEqual(["fix"]);
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: [] })).toEqual(["fix"]);
  });

  it("reports every missing nested key", () => {
    expect(fieldsOf(fulfillLocateRequestRequestSchema, { fix: {} })).toEqual([
      "fix.fixId",
      "fix.recordedAt",
      "fix.lat",
      "fix.lon",
      "fix.accuracyM",
      "fix.batteryPct",
      "fix.source",
    ]);
  });
});

describe("failure paths: object-level refinements and their interaction with field issues", () => {
  it("passes a refinement when any one qualifying field is present", () => {
    expect(accepts(patchDeviceSettingsRequestSchema, { trackingEnabled: false })).toBe(true);
    expect(accepts(patchDeviceSettingsRequestSchema, { staleNudgeEnabled: false })).toBe(true);
    expect(accepts(patchDeviceSettingsRequestSchema, { deviceName: "d" })).toBe(true);
    expect(accepts(patchDeviceSettingsRequestSchema, { pushToken: "t" })).toBe(true);
    expect(accepts(updateMemberRequestSchema, { role: "parent" })).toBe(true);
    expect(accepts(updateMemberRequestSchema, { displayName: "E" })).toBe(true);
    expect(accepts(patchGroupRequestSchema, { name: "G" })).toBe(true);
  });

  it("treats explicit undefined values as absent for the refinement", () => {
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { trackingEnabled: undefined })).toEqual(["(root)"]);
    expect(fieldsOf(updateMemberRequestSchema, { role: undefined, displayName: undefined })).toEqual(["(root)"]);
  });

  it("ignores unknown keys when judging 'at least one field' (they are stripped first)", () => {
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { somethingElse: 1 })).toEqual(["(root)"]);
    expect(fieldsOf(updateMemberRequestSchema, { somethingElse: 1 })).toEqual(["(root)"]);
    expect(fieldsOf(patchGroupRequestSchema, { somethingElse: 1 })).toEqual(["(root)"]);
  });

  it("reports ONLY the field path, no extra (root), when a field has the wrong TYPE (refinement is skipped)", () => {
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { trackingEnabled: "yes" })).toEqual(["trackingEnabled"]);
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { syncIntervalMinutes: "15" })).toEqual(["syncIntervalMinutes"]);
    expect(fieldsOf(updateMemberRequestSchema, { role: 5 })).toEqual(["role"]);
    expect(fieldsOf(patchGroupRequestSchema, { name: 5 })).toEqual(["name"]);
  });

  it("reports ONLY the field path when the failing field also satisfies the refinement (rule failure, refinement passes)", () => {
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { deviceName: "" })).toEqual(["deviceName"]);
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { deviceName: "d".repeat(41) })).toEqual(["deviceName"]);
    expect(fieldsOf(patchDeviceSettingsRequestSchema, { pushToken: "" })).toEqual(["pushToken"]);
    expect(fieldsOf(patchGroupRequestSchema, { name: "" })).toEqual(["name"]);
    expect(fieldsOf(patchGroupRequestSchema, { name: "x".repeat(51) })).toEqual(["name"]);
    expect(fieldsOf(patchGroupRequestSchema, { endsAt: "tomorrow" })).toEqual(["endsAt"]);
    expect(fieldsOf(updateMemberRequestSchema, { displayName: "‮" })).toEqual(["displayName"]);
  });

  it("locate request: exactly one of targetUserId / targetDeviceId (both or neither -> (root))", () => {
    expect(accepts(createLocateRequestRequestSchema, { targetUserId: "u1" })).toBe(true);
    expect(accepts(createLocateRequestRequestSchema, { targetDeviceId: UUID_A })).toBe(true);
    expect(fieldsOf(createLocateRequestRequestSchema, { targetUserId: "u1", targetDeviceId: UUID_A })).toEqual(["(root)"]);
    expect(fieldsOf(createLocateRequestRequestSchema, {})).toEqual(["(root)"]);
    expect(fieldsOf(createLocateRequestRequestSchema, { targetUserId: undefined, targetDeviceId: undefined })).toEqual(["(root)"]);
  });

  it("locate request: field issues of the wrong TYPE suppress the refinement; format/size issues do not", () => {
    expect(fieldsOf(createLocateRequestRequestSchema, { targetUserId: 5 })).toEqual(["targetUserId"]);
    expect(fieldsOf(createLocateRequestRequestSchema, { targetDeviceId: "not-a-uuid" })).toEqual(["targetDeviceId"]);
    expect(fieldsOf(createLocateRequestRequestSchema, { targetUserId: "" })).toEqual(["targetUserId"]);
    expect(fieldsOf(createLocateRequestRequestSchema, { targetUserId: 5, targetDeviceId: UUID_A })).toEqual(["targetUserId"]);
    // Non-aborting field issue on BOTH keys: the refinement still runs and also reports (root).
    expect(fieldsOf(createLocateRequestRequestSchema, { targetUserId: "", targetDeviceId: "not-a-uuid" })).toEqual([
      "targetUserId",
      "targetDeviceId",
      "(root)",
    ]);
  });
});

describe("failure paths: query-string schemas (z.coerce.number)", () => {
  const BASE_HISTORY = { userId: "u1", from: "2026-07-01", to: "2026-07-05" };

  it("coerces limit from its string form and keeps it optional", () => {
    const result = run(locationHistoryQuerySchema, { ...BASE_HISTORY, limit: "25" });
    expect(result.ok && result.data.limit).toBe(25);
    const absent = run(locationHistoryQuerySchema, BASE_HISTORY);
    expect(absent.ok && absent.data.limit).toBeUndefined();
    const events = run(geofenceEventHistoryQuerySchema, { from: "2026-07-01", to: "2026-07-05", limit: "500" });
    expect(events.ok && events.data.limit).toBe(500);
  });

  it("rejects out-of-range, non-integer and non-numeric limits on the limit path", () => {
    for (const limit of ["0", "501", "1.5", "abc", "-1", "", "NaN", "1e9"]) {
      expect(fieldsOf(locationHistoryQuerySchema, { ...BASE_HISTORY, limit }), JSON.stringify(limit)).toEqual(["limit"]);
      expect(fieldsOf(geofenceEventHistoryQuerySchema, { from: "a", to: "b", limit }), JSON.stringify(limit)).toEqual(["limit"]);
    }
  });

  it("accepts the limit boundaries 1 and 500", () => {
    for (const limit of ["1", "500"]) expect(accepts(locationHistoryQuerySchema, { ...BASE_HISTORY, limit })).toBe(true);
  });

  it("reports missing required query params in key order, and rejects empty strings", () => {
    expect(fieldsOf(locationHistoryQuerySchema, {})).toEqual(["userId", "from", "to"]);
    expect(fieldsOf(locationHistoryQuerySchema, { userId: "", from: "", to: "" })).toEqual(["userId", "from", "to"]);
    expect(fieldsOf(locationHistoryQuerySchema, { ...BASE_HISTORY, deviceId: "" })).toEqual(["deviceId"]);
    expect(fieldsOf(locationHistoryQuerySchema, { ...BASE_HISTORY, cursor: "" })).toEqual(["cursor"]);
    expect(fieldsOf(geofenceEventHistoryQuerySchema, {})).toEqual(["from", "to"]);
    expect(fieldsOf(geofenceEventHistoryQuerySchema, { from: "a", to: "b", userId: "" })).toEqual(["userId"]);
  });
});

describe("failure paths: param schemas", () => {
  it("reports the param name for a missing or non-string path param", () => {
    expect(fieldsOf(deviceIdParamSchema, {})).toEqual(["deviceId"]);
    expect(fieldsOf(deviceIdParamSchema, { deviceId: 5 })).toEqual(["deviceId"]);
    expect(fieldsOf(groupIdParamSchema, {})).toEqual(["groupId"]);
    expect(fieldsOf(memberUserIdParamSchema, {})).toEqual(["userId"]);
  });

  it("rejects control characters (\\p{Cc}) but accepts other Unicode in a Table Storage key param", () => {
    expect(fieldsOf(memberUserIdParamSchema, { userId: "a\u0000b" })).toEqual(["userId"]);
    expect(fieldsOf(memberUserIdParamSchema, { userId: "a\u007Fb" })).toEqual(["userId"]);
    expect(fieldsOf(memberUserIdParamSchema, { userId: "a\u0085b" })).toEqual(["userId"]);
    expect(fieldsOf(memberUserIdParamSchema, { userId: "a\nb" })).toEqual(["userId"]);
    expect(accepts(memberUserIdParamSchema, { userId: "José-中文-🚀 with space" })).toBe(true);
    expect(accepts(memberUserIdParamSchema, { userId: "firebase|uid_123.abc" })).toBe(true);
  });

  it("counts the 128-char bound in UTF-16 code units", () => {
    // 64 emoji = 128 code units (accepted); 65 = 130 (rejected).
    expect(accepts(memberUserIdParamSchema, { userId: "🚀".repeat(64) })).toBe(true);
    expect(fieldsOf(memberUserIdParamSchema, { userId: "🚀".repeat(65) })).toEqual(["userId"]);
  });
});

describe("failure paths: cross-schema accepts-as-valid sanity (guards against over-tightening)", () => {
  it("accepts a fully valid body for every body schema", () => {
    expect(accepts(createFamilyRequestSchema, { familyName: "W", displayName: "E" })).toBe(true);
    expect(accepts(registerDeviceRequestSchema, validDevice({ pushToken: "t", locationPushToken: "l", deviceName: "d" }))).toBe(true);
    expect(accepts(reportLocationsRequestSchema, { batchId: UUID_B, fixes: [validFix()] })).toBe(true);
    expect(accepts(replaceGeofencesRequestSchema, { geofences: [validGeofence()] })).toBe(true);
    expect(accepts(acceptInviteRequestSchema, { inviteCode: "ABCD-EFGH", displayName: "E" })).toBe(true);
    expect(accepts(createGroupRequestSchema, { name: "G", endsAt: "2026-12-01T00:00:00Z", expiryPolicy: "grace", displayName: "E" })).toBe(true);
    expect(accepts(fulfillLocateRequestRequestSchema, { fix: validFix({ source: "locate" }) })).toBe(true);
  });
});
