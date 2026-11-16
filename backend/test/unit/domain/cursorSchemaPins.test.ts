// specs/002 §3.3 / 001 §10 — B40 characterisation of the cursor schemas' accept/reject
// decisions (src/domain/history/cursor.ts), written GREEN on zod 3 and kept UNCHANGED across
// the zod 4 migration. Every rejection surfaces as VALIDATION_FAILED, details.fields ["cursor"],
// whatever the underlying zod issue is; only the accept/reject boundary can drift.

import { describe, expect, it } from "vitest";
import { decodeEventCursor, decodeFixCursor } from "../../../src/domain/history/cursor";
import { AppError } from "../../../src/http/errors";

function raw(value: unknown): string {
  return Buffer.from(JSON.stringify(value), "utf-8").toString("base64url");
}

function rejects(decode: (raw: string) => unknown, encoded: string): void {
  let caught: unknown;
  try {
    decode(encoded);
  } catch (error) {
    caught = error;
  }
  expect(caught).toBeInstanceOf(AppError);
  const error = caught as AppError;
  expect(error.code).toBe("VALIDATION_FAILED");
  expect(error.message).toBe("cursor is not a valid cursor");
  expect(error.details).toEqual({ fields: ["cursor"] });
}

describe("cursor schema accept/reject boundary (B40 pin)", () => {
  it("fix cursor: accepts non-negative integer offsets (including 0 and large) and an empty offset map", () => {
    expect(decodeFixCursor(raw({ d: "2026-07-05", o: {} }))).toEqual({ d: "2026-07-05", o: {} });
    expect(decodeFixCursor(raw({ d: "2026-07-05", o: { a: 0, b: 9007199254740991 } }))).toEqual({
      d: "2026-07-05",
      o: { a: 0, b: 9007199254740991 },
    });
  });

  it("fix cursor: rejects negative, fractional, string, null and boolean offsets inside the record", () => {
    for (const bad of [-1, 1.5, "3", null, true, [], {}]) {
      rejects(decodeFixCursor, raw({ d: "2026-07-05", o: { a: bad } }));
    }
  });

  it("fix cursor: rejects a missing or non-string date and a missing, null, array or primitive offset map", () => {
    rejects(decodeFixCursor, raw({ o: {} }));
    rejects(decodeFixCursor, raw({ d: 20260705, o: {} }));
    rejects(decodeFixCursor, raw({ d: null, o: {} }));
    rejects(decodeFixCursor, raw({ d: "2026-07-05" }));
    rejects(decodeFixCursor, raw({ d: "2026-07-05", o: null }));
    rejects(decodeFixCursor, raw({ d: "2026-07-05", o: [] }));
    rejects(decodeFixCursor, raw({ d: "2026-07-05", o: 5 }));
  });

  it("fix cursor: strips unknown top-level keys instead of rejecting", () => {
    expect(decodeFixCursor(raw({ d: "2026-07-05", o: { a: 1 }, extra: "x" }))).toEqual({ d: "2026-07-05", o: { a: 1 } });
  });

  it("fix cursor: rejects non-object JSON payloads", () => {
    for (const payload of [null, 5, "x", [], true]) rejects(decodeFixCursor, raw(payload));
  });

  it("event cursor: accepts a non-negative integer offset and rejects negative, fractional, string and missing ones", () => {
    expect(decodeEventCursor(raw({ d: "2026-07-05", o: 0 }))).toEqual({ d: "2026-07-05", o: 0 });
    expect(decodeEventCursor(raw({ d: "2026-07-05", o: 9007199254740991 }))).toEqual({ d: "2026-07-05", o: 9007199254740991 });
    for (const bad of [-1, 1.5, "3", null, true, [], {}]) rejects(decodeEventCursor, raw({ d: "2026-07-05", o: bad }));
    rejects(decodeEventCursor, raw({ d: "2026-07-05" }));
    rejects(decodeEventCursor, raw({ o: 1 }));
  });

  it("event cursor: strips unknown keys and rejects non-object payloads", () => {
    expect(decodeEventCursor(raw({ d: "2026-07-05", o: 1, extra: 1 }))).toEqual({ d: "2026-07-05", o: 1 });
    for (const payload of [null, 5, "x", [], true]) rejects(decodeEventCursor, raw(payload));
  });

  it("rejects an empty cursor string and undecodable base64url/JSON for both decoders", () => {
    for (const bad of ["", "!!!", Buffer.from("{not json", "utf-8").toString("base64url")]) {
      rejects(decodeFixCursor, bad);
      rejects(decodeEventCursor, bad);
    }
  });

  it("date shape is YYYY-MM-DD digits only (calendar validity is the domain's job): 9999-99-99 passes, 2026-7-5 does not", () => {
    expect(decodeEventCursor(raw({ d: "9999-99-99", o: 1 }))).toEqual({ d: "9999-99-99", o: 1 });
    rejects(decodeEventCursor, raw({ d: "2026-7-5", o: 1 }));
    rejects(decodeEventCursor, raw({ d: "2026-07-05\n", o: 1 }));
    rejects(decodeEventCursor, raw({ d: "", o: 1 }));
  });
});
