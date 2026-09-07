// specs/001 §4.1 devices.functions.ts's catch-all — proves the actual wiring (not just the
// extracted src/http/errorLogging helper) sanitizes what it hands to context.error. This
// file is normally thin/untested (backend/README.md: "src/functions ... thin integration
// surface ... excluded from mutation"); every real dependency is mocked here purely so the
// module can be imported and its handler invoked without touching Azurite/Firebase/FCM —
// `npm test` must never require Azurite (CLAUDE.md) — the mutation-tested logic itself
// lives in src/http/errorLogging and is covered by errorLogging.test.ts.

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

class FakeAzureRestError extends Error {
  code = "ETIMEDOUT";
  // Real Azure RestErrors carry these — the whole point of this task is that they must
  // never reach context.error.
  request = { url: "https://storage.example/devstoreaccount1/Devices", headers: { Authorization: "Bearer leak-me" } };
  response = { bodyAsText: "leaked response body" };
}

vi.mock("../../../src/domain/device/registerDevice", () => ({
  registerDevice: vi.fn().mockRejectedValue(new FakeAzureRestError("connection timed out")),
}));
vi.mock("../../../src/domain/device/listMyDevices", () => ({ listMyDevices: vi.fn() }));
vi.mock("../../../src/domain/device/patchDeviceSettings", () => ({ patchDeviceSettings: vi.fn() }));

vi.mock("../../../src/adapters/auth/firebaseJoseVerifier", () => ({ createTokenVerifier: () => ({}) }));
vi.mock("../../../src/adapters/tables/usersTableRepo", () => ({ TableUserRepo: class {} }));
vi.mock("../../../src/adapters/tables/familiesTableRepo", () => ({ TableFamilyRepo: class {} }));
vi.mock("../../../src/adapters/tables/devicesTableRepo", () => ({ TableDeviceRepo: class {} }));
vi.mock("../../../src/adapters/tables/entitlementsTableRepo", () => ({ TableEntitlementsRepo: class {} }));
vi.mock("../../../src/adapters/tables/usageTableRepo", () => ({ TableUsageRepo: class {} }));
vi.mock("../../../src/adapters/push/fcmV1Sender", () => ({ FcmV1Sender: class {} }));
vi.mock("../../../src/adapters/support/systemClock", () => ({ SystemClock: class {} }));

beforeEach(() => {
  vi.resetModules();
  for (const key of Object.keys(registeredHandlers)) delete registeredHandlers[key];
});

describe("functions/devices.functions registerDevice catch-all", () => {
  it("logs only { message, code } to context.error — never the raw error object", async () => {
    await import("../../../src/functions/devices.functions");
    const contextError = vi.fn();
    const context = { error: contextError, log: vi.fn(), warn: vi.fn(), info: vi.fn() };
    const request = { headers: { get: () => "Bearer sometoken" }, json: async () => ({}) };

    // registeredHandlers is a Record<string, ...>, so noUncheckedIndexedAccess types this
    // lookup as possibly undefined — the import above is what actually populates it.
    const registerDeviceHandler = registeredHandlers.registerDevice;
    if (!registerDeviceHandler) throw new Error("test setup: devices.functions.ts should have registered registerDevice");
    await registerDeviceHandler(request, context);

    expect(contextError).toHaveBeenCalledTimes(1);
    const call = contextError.mock.calls[0];
    if (!call) throw new Error("test setup: contextError should have been called");
    const [label, logged] = call;
    expect(label).toBe("unhandled error in registerDevice");
    expect(logged).toEqual({ message: "connection timed out", code: "ETIMEDOUT" });
    expect(logged).not.toHaveProperty("request");
    expect(logged).not.toHaveProperty("response");
    expect(logged).not.toBeInstanceOf(Error);
  });
});
