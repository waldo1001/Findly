// specs/002 §4.1 groupSweeper.functions.ts's unhandled-error catch-all — same rationale as
// devices.functions.test.ts: proves the actual timer-trigger wiring sanitizes what it hands
// to context.error, without touching Azurite/Firebase (every dependency mocked).

import { beforeEach, describe, expect, it, vi } from "vitest";

const registeredHandlers: Record<string, (timer: unknown, context: unknown) => Promise<unknown>> = {};

vi.mock("@azure/functions", () => ({
  app: {
    timer: (name: string, config: { handler: (timer: unknown, context: unknown) => Promise<unknown> }) => {
      registeredHandlers[name] = config.handler;
    },
  },
}));

class FakeAzureRestError extends Error {
  code = "ETIMEDOUT";
  request = { url: "https://storage.example/devstoreaccount1/Groups", headers: { Authorization: "Bearer leak-me" } };
  response = { bodyAsText: "leaked response body" };
}

vi.mock("../../../src/domain/group/groupSweeper", () => ({
  sweepGroups: vi.fn().mockRejectedValue(new FakeAzureRestError("connection timed out")),
}));
vi.mock("../../../src/adapters/tables/usersTableRepo", () => ({ TableUserRepo: class {} }));
vi.mock("../../../src/adapters/tables/groupsTableRepo", () => ({ TableGroupRepo: class {} }));
vi.mock("../../../src/adapters/tables/groupCodesTableRepo", () => ({ TableGroupCodeRepo: class {} }));
vi.mock("../../../src/adapters/tables/groupExpiryTableRepo", () => ({ TableGroupExpiryRepo: class {} }));
vi.mock("../../../src/adapters/tables/groupLastKnownTableRepo", () => ({ TableGroupLastKnownRepo: class {} }));
vi.mock("../../../src/adapters/tables/entitlementsTableRepo", () => ({ TableEntitlementsRepo: class {} }));
vi.mock("../../../src/adapters/support/systemClock", () => ({ SystemClock: class {} }));

beforeEach(() => {
  vi.resetModules();
  for (const key of Object.keys(registeredHandlers)) delete registeredHandlers[key];
});

describe("functions/groupSweeper.functions unhandled-error catch-all", () => {
  it("logs only { message, code } to context.error — never the raw error object", async () => {
    await import("../../../src/functions/groupSweeper.functions");
    const contextError = vi.fn();
    const context = { error: contextError, log: vi.fn(), warn: vi.fn(), info: vi.fn() };

    // registeredHandlers is a Record<string, ...>, so noUncheckedIndexedAccess types this
    // lookup as possibly undefined — the import above is what actually populates it.
    const groupSweeperHandler = registeredHandlers.groupSweeper;
    if (!groupSweeperHandler) throw new Error("test setup: groupSweeper.functions.ts should have registered groupSweeper");
    await groupSweeperHandler({}, context);

    expect(contextError).toHaveBeenCalledTimes(1);
    const call = contextError.mock.calls[0];
    if (!call) throw new Error("test setup: contextError should have been called");
    const [label, logged] = call;
    expect(label).toBe("groupSweeper: unhandled error");
    expect(logged).toEqual({ message: "connection timed out", code: "ETIMEDOUT" });
    expect(logged).not.toHaveProperty("request");
    expect(logged).not.toHaveProperty("response");
    expect(logged).not.toBeInstanceOf(Error);
  });
});
