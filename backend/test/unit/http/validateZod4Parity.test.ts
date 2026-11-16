// B40 - additive pins for the three zod 4 parity helpers in src/http/validate.ts
// (maxUnits, uuidString, utcDatetimeString). Complements validateEnvelope.test.ts, which
// holds the zod 3 characterisation; nothing here relaxes it.

import { describe, expect, it } from "vitest";
import {
  createFamilyRequestSchema,
  deviceIdParamSchema,
  geofenceEntryRequestSchema,
  locationFixSchema,
  memberUserIdParamSchema,
  parseOrThrow,
  registerDeviceRequestSchema,
} from "../../../src/http/validate";
import { AppError } from "../../../src/http/errors";

function accepts(schema: Parameters<typeof parseOrThrow>[0], input: unknown): boolean {
  try {
    parseOrThrow(schema, input);
    return true;
  } catch (error) {
    if (error instanceof AppError) return false;
    throw error;
  }
}

const FIX = {
  fixId: "3e0f2a9c-6b1d-4e8f-9a2b-7c5d4e3f2a1b",
  recordedAt: "2026-07-05T10:00:00Z",
  lat: 1,
  lon: 1,
  accuracyM: 1,
  batteryPct: 1,
  source: "periodic",
};

describe("minute-precision UTC datetime (kept from zod 3.25; seconds default to :00)", () => {
  it("accepts a valid minute-precision instant", () => {
    expect(accepts(locationFixSchema, { ...FIX, recordedAt: "2026-07-05T10:00Z" })).toBe(true);
    expect(accepts(locationFixSchema, { ...FIX, recordedAt: "2026-07-05T23:59Z" })).toBe(true);
  });

  it("still applies the calendar and clock rules to the minute-precision form", () => {
    for (const recordedAt of ["2026-13-05T10:00Z", "2026-02-30T10:00Z", "2026-07-05T24:00Z", "2026-07-05T10:60Z", "2026-07-05T1:00Z"]) {
      expect(accepts(locationFixSchema, { ...FIX, recordedAt }), recordedAt).toBe(false);
    }
  });

  it("does not extend the minute form to offsets, local times or trailing junk", () => {
    for (const recordedAt of ["2026-07-05T10:00+02:00", "2026-07-05T10:00", "2026-07-05T10:00ZZ", "2026-07-05T10:00Z\n", "x2026-07-05T10:00Z"]) {
      expect(accepts(locationFixSchema, { ...FIX, recordedAt }), JSON.stringify(recordedAt)).toBe(false);
    }
  });
});

describe("string upper bounds count UTF-16 code units, not code points (zod 3 behaviour)", () => {
  const rocket = "\u{1F680}"; // 2 UTF-16 units, 1 code point

  it("rejects 16 emoji (32 units) for a 30-unit displayName, accepts 15 (30 units)", () => {
    expect(accepts(createFamilyRequestSchema, { familyName: "W", displayName: rocket.repeat(15) })).toBe(true);
    expect(accepts(createFamilyRequestSchema, { familyName: "W", displayName: rocket.repeat(16) })).toBe(false);
  });

  it("applies the same unit counting to plain max-bounded strings (model <= 60, familyName <= 50, icon <= 30)", () => {
    const device = { deviceId: FIX.fixId, platform: "ios", appVersion: "1" };
    expect(accepts(registerDeviceRequestSchema, { ...device, model: rocket.repeat(30) })).toBe(true);
    expect(accepts(registerDeviceRequestSchema, { ...device, model: rocket.repeat(31) })).toBe(false);
    expect(accepts(createFamilyRequestSchema, { familyName: rocket.repeat(25), displayName: "E" })).toBe(true);
    expect(accepts(createFamilyRequestSchema, { familyName: rocket.repeat(26), displayName: "E" })).toBe(false);
    const geofence = { geofenceId: "gf_a", name: "n", lat: 1, lon: 1, radiusM: 100, notifyOnEnter: true, notifyOnExit: true };
    expect(accepts(geofenceEntryRequestSchema, { ...geofence, icon: rocket.repeat(15) })).toBe(true);
    expect(accepts(geofenceEntryRequestSchema, { ...geofence, icon: rocket.repeat(16) })).toBe(false);
  });

  it("keeps the 128-unit userId cap and the min(1) floor independent", () => {
    expect(accepts(memberUserIdParamSchema, { userId: "a".repeat(128) })).toBe(true);
    expect(accepts(memberUserIdParamSchema, { userId: "a".repeat(129) })).toBe(false);
    expect(accepts(memberUserIdParamSchema, { userId: "" })).toBe(false);
  });
});

describe("UUID shape (zod 3 permissive 8-4-4-4-12 hex, kept via z.guid)", () => {
  it("accepts a non-RFC-variant UUID and rejects a malformed one on every uuid-typed field", () => {
    expect(accepts(deviceIdParamSchema, { deviceId: "11111111-1111-1111-1111-111111111111" })).toBe(true);
    expect(accepts(deviceIdParamSchema, { deviceId: "11111111-1111-1111-1111-11111111111" })).toBe(false);
    expect(accepts(locationFixSchema, { ...FIX, fixId: "11111111-1111-1111-1111-111111111111" })).toBe(true);
    expect(accepts(locationFixSchema, { ...FIX, fixId: "11111111111111111111111111111111" })).toBe(false);
  });
});
