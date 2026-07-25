// specs/001 §1.3/§13.1 — export.functions.ts is the ONE handler in this codebase that must
// NOT call http/envelope's ok() on success: the response is the unenveloped export document
// itself with an attachment Content-Disposition header. Functions files are normally
// thin/untested (backend/README.md), but this wiring detail is genuinely easy to get wrong
// (every other endpoint's success path is the boilerplate `{status, jsonBody: ok(...)}`), so
// it gets a light wiring test here — same mocking style as devices.functions.test.ts, which
// proves the shared error-sanitization catch-all.

import { beforeEach, describe, expect, it, vi } from "vitest";

const registeredHandlers: Record<string, (request: unknown, context: unknown) => Promise<unknown>> = {};

vi.mock("@azure/functions", () => ({
  app: {
    http: (name: string, config: { handler: (request: unknown, context: unknown) => Promise<unknown> }) => {
      registeredHandlers[name] = config.handler;
    },
  },
}));

vi.mock("../../../src/http/authGuard", () => ({
  authenticate: vi.fn().mockResolvedValue({ uid: "u1", familyId: "fam_12345678901234567890", role: "parent" }),
}));

const exportUserDataMock = vi.fn();
vi.mock("../../../src/domain/export/exportUserData", () => ({ exportUserData: exportUserDataMock }));

vi.mock("../../../src/adapters/auth/firebaseJoseVerifier", () => ({ createTokenVerifier: () => ({}) }));
vi.mock("../../../src/adapters/tables/usersTableRepo", () => ({ TableUserRepo: class {} }));
vi.mock("../../../src/adapters/tables/familiesTableRepo", () => ({ TableFamilyRepo: class {} }));
vi.mock("../../../src/adapters/tables/devicesTableRepo", () => ({ TableDeviceRepo: class {} }));
vi.mock("../../../src/adapters/tables/lastKnownTableRepo", () => ({ TableLastKnownRepo: class {} }));
vi.mock("../../../src/adapters/tables/groupsTableRepo", () => ({ TableGroupRepo: class {} }));
vi.mock("../../../src/adapters/tables/groupLastKnownTableRepo", () => ({ TableGroupLastKnownRepo: class {} }));
vi.mock("../../../src/adapters/tables/entitlementsTableRepo", () => ({ TableEntitlementsRepo: class {} }));
vi.mock("../../../src/adapters/tables/usageTableRepo", () => ({ TableUsageRepo: class {} }));
vi.mock("../../../src/adapters/blobs/historyBlobStore", () => ({ BlobHistoryStore: class {} }));
vi.mock("../../../src/adapters/support/systemClock", () => ({ SystemClock: class {} }));

function fakeRequest(query: Record<string, string> = {}) {
  return {
    headers: { get: () => "Bearer sometoken" },
    query: new URLSearchParams(query),
  };
}

beforeEach(() => {
  vi.resetModules();
  exportUserDataMock.mockReset();
  for (const key of Object.keys(registeredHandlers)) delete registeredHandlers[key];
});

describe("functions/export.functions", () => {
  it("returns the export document UNENVELOPED (no {data, features} wrapper) with attachment headers", async () => {
    const doc = {
      formatVersion: 1,
      generatedAt: "2026-07-25T14:00:00.000Z",
      subject: { userId: "u2", displayName: "Noor" },
      family: null,
      devices: [],
      lastKnown: [],
      locationHistory: [],
      geofenceEvents: [],
      groups: [],
      groupPositions: [],
      usage: [],
      providerData: { firebaseAuthentication: "note" },
    };
    exportUserDataMock.mockResolvedValue(doc);

    await import("../../../src/functions/export.functions");
    const context = { error: vi.fn(), log: vi.fn(), warn: vi.fn(), info: vi.fn() };

    const response = (await registeredHandlers.exportUserData!(fakeRequest(), context)) as {
      status: number;
      headers: Record<string, string>;
      body: string;
      jsonBody?: unknown;
    };

    expect(response.status).toBe(200);
    expect(response.headers["Content-Type"]).toBe("application/json; charset=utf-8");
    expect(response.headers["Content-Disposition"]).toBe('attachment; filename="findly-export-u2-2026-07-25.json"');
    expect(response.jsonBody).toBeUndefined();
    expect(JSON.parse(response.body)).toEqual(doc);
    // Not enveloped: no top-level "data"/"features" keys wrapping the document.
    expect(JSON.parse(response.body)).not.toHaveProperty("data");
    expect(JSON.parse(response.body)).not.toHaveProperty("features");
  });

  it("still returns the normal enveloped error shape on an AppError (e.g. LIMIT_EXCEEDED)", async () => {
    const { AppError } = await import("../../../src/http/errors");
    exportUserDataMock.mockRejectedValue(new AppError("LIMIT_EXCEEDED", "quota", { limit: "exportsPerDay" }));

    await import("../../../src/functions/export.functions");
    const context = { error: vi.fn(), log: vi.fn(), warn: vi.fn(), info: vi.fn() };

    const response = (await registeredHandlers.exportUserData!(fakeRequest(), context)) as {
      status: number;
      jsonBody: { error: { code: string; details?: unknown } };
    };

    expect(response.status).toBe(402);
    expect(response.jsonBody.error.code).toBe("LIMIT_EXCEEDED");
    expect(response.jsonBody.error.details).toEqual({ limit: "exportsPerDay" });
  });

  it("logs only { message, code } to context.error on an unexpected throw — never the raw error object", async () => {
    class FakeAzureRestError extends Error {
      code = "ETIMEDOUT";
      request = { url: "https://storage.example/devstoreaccount1/Usage", headers: { Authorization: "Bearer leak-me" } };
      response = { bodyAsText: "leaked response body" };
    }
    exportUserDataMock.mockRejectedValue(new FakeAzureRestError("connection timed out"));

    await import("../../../src/functions/export.functions");
    const contextError = vi.fn();
    const context = { error: contextError, log: vi.fn(), warn: vi.fn(), info: vi.fn() };

    const response = (await registeredHandlers.exportUserData!(fakeRequest(), context)) as { status: number };

    expect(response.status).toBe(500);
    expect(contextError).toHaveBeenCalledTimes(1);
    const [label, logged] = contextError.mock.calls[0];
    expect(label).toBe("unhandled error in exportUserData");
    expect(logged).toEqual({ message: "connection timed out", code: "ETIMEDOUT" });
    expect(logged).not.toHaveProperty("request");
    expect(logged).not.toHaveProperty("response");
  });
});
