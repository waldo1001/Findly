// specs/011 §4.2 — staleNudger.functions.ts wiring: schedule, the STALE_NUDGE_ENABLED gate passed
// through, counts-only logging, sanitized error logging. Every dependency mocked.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const registered: Record<string, { schedule: string; handler: (t: unknown, c: unknown) => Promise<unknown> }> = {};

vi.mock("@azure/functions", () => ({
  app: {
    timer: (name: string, config: { schedule: string; handler: (t: unknown, c: unknown) => Promise<unknown> }) => {
      registered[name] = config;
    },
  },
}));

const runStaleNudge = vi.fn();
vi.mock("../../../src/domain/device/staleNudge", () => ({ runStaleNudge: (deps: unknown) => runStaleNudge(deps) }));
vi.mock("../../../src/adapters/tables/devicesTableRepo", () => ({ TableDeviceRepo: class {} }));
vi.mock("../../../src/adapters/push/fcmV1Sender", () => ({ FcmV1Sender: class {} }));
vi.mock("../../../src/adapters/support/systemClock", () => ({ SystemClock: class {} }));

class FakeAzureRestError extends Error {
  code = "ETIMEDOUT";
  request = { url: "https://storage.example/devstoreaccount1/Devices", headers: { Authorization: "Bearer leak-me" } };
  response = { bodyAsText: "leaked response body" };
}

const original = process.env.STALE_NUDGE_ENABLED;

beforeEach(() => {
  vi.resetModules();
  runStaleNudge.mockReset();
  for (const key of Object.keys(registered)) delete registered[key];
});

afterEach(() => {
  if (original === undefined) delete process.env.STALE_NUDGE_ENABLED;
  else process.env.STALE_NUDGE_ENABLED = original;
});

async function load() {
  await import("../../../src/functions/staleNudger.functions");
  const entry = registered.staleNudger;
  if (!entry) throw new Error("test setup: staleNudger.functions.ts should have registered staleNudger");
  return entry;
}

const ctx = () => ({ error: vi.fn(), log: vi.fn(), warn: vi.fn(), info: vi.fn() });

describe("functions/staleNudger.functions", () => {
  it("runs every 30 minutes (002 §4.3)", async () => {
    expect((await load()).schedule).toBe("0 */30 * * * *");
  });

  it("passes the raw STALE_NUDGE_ENABLED setting to the domain", async () => {
    runStaleNudge.mockResolvedValue({ enabled: true, evaluated: 0, due: 0, sent: 0, failed: 0 });
    process.env.STALE_NUDGE_ENABLED = "true";
    const { handler } = await load();
    await handler({}, ctx());
    expect(runStaleNudge.mock.calls[0]?.[0]).toMatchObject({ enabledSetting: "true" });
  });

  it("an absent setting is passed as undefined (domain treats it as off)", async () => {
    runStaleNudge.mockResolvedValue({ enabled: false, evaluated: 0, due: 0, sent: 0, failed: 0 });
    delete process.env.STALE_NUDGE_ENABLED;
    const { handler } = await load();
    await handler({}, ctx());
    expect(runStaleNudge.mock.calls[0]?.[0]).toMatchObject({ enabledSetting: undefined });
  });

  it("logs counts only", async () => {
    runStaleNudge.mockResolvedValue({ enabled: true, evaluated: 9, due: 3, sent: 2, failed: 1 });
    const { handler } = await load();
    const context = ctx();
    await handler({}, context);
    expect(context.log).toHaveBeenCalledWith("staleNudger: enabled=true evaluated=9 due=3 sent=2 failed=1");
  });

  it("logs only { message, code } on an unhandled error — never the raw error object", async () => {
    runStaleNudge.mockRejectedValue(new FakeAzureRestError("connection timed out"));
    const { handler } = await load();
    const context = ctx();
    await handler({}, context);
    expect(context.error).toHaveBeenCalledTimes(1);
    const [label, logged] = context.error.mock.calls[0] ?? [];
    expect(label).toBe("staleNudger: unhandled error");
    expect(logged).toEqual({ message: "connection timed out", code: "ETIMEDOUT" });
    expect(logged).not.toBeInstanceOf(Error);
  });
});
