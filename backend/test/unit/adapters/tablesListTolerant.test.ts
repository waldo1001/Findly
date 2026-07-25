// specs/002 §4.2 (normative), specs/008 §9 (B20) — unit coverage for the shared helper every
// table adapter's list/enumerate step now funnels through (src/adapters/tables/listTolerant.ts).
// Pure logic, no Azure SDK network calls — fast, no Azurite required (CLAUDE.md: `npm test`
// must never require Azurite). The critical case here is the NEGATIVE CONTROL: a genuine
// non-404 storage error (403/500) must still propagate, proving the fix doesn't over-swallow.

import { describe, expect, it } from "vitest";
import { RestError } from "@azure/data-tables";
import { collectEntitiesTolerant } from "../../../src/adapters/tables/listTolerant";

/** A minimal AsyncIterable that yields `items` then either completes or throws `failWith`. */
function fakeIterable<T>(items: T[], failWith?: unknown): AsyncIterable<T> {
  return {
    [Symbol.asyncIterator]() {
      let index = 0;
      return {
        async next(): Promise<IteratorResult<T>> {
          if (index < items.length) {
            const value = items[index] as T;
            index += 1;
            return { value, done: false };
          }
          if (failWith !== undefined) {
            const err = failWith;
            failWith = undefined; // only throw once
            throw err;
          }
          return { value: undefined as unknown as T, done: true };
        },
      };
    },
  };
}

describe("unit/adapters/tables/listTolerant — collectEntitiesTolerant (specs/002 §4.2, 008 §9, B20)", () => {
  it("drains a normal iterator into an array", async () => {
    const iterable = fakeIterable([{ rowKey: "a" }, { rowKey: "b" }]);

    await expect(collectEntitiesTolerant(iterable)).resolves.toEqual([{ rowKey: "a" }, { rowKey: "b" }]);
  });

  it("resolves to an empty array when the table has never been created (TableNotFound, 404) — the exact live B20 failure mode", async () => {
    const tableNotFound = new RestError("The table specified does not exist.", {
      statusCode: 404,
      code: "TableNotFound",
    });
    const iterable = fakeIterable<{ rowKey: string }>([], tableNotFound);

    await expect(collectEntitiesTolerant(iterable)).resolves.toEqual([]);
  });

  it("resolves to an empty array for any 404, even without a recognized error code", async () => {
    const genericNotFound = new RestError("not found", { statusCode: 404 });
    const iterable = fakeIterable<{ rowKey: string }>([], genericNotFound);

    await expect(collectEntitiesTolerant(iterable)).resolves.toEqual([]);
  });

  it("does not discard rows already collected before a 404 arrives on a later page", async () => {
    const tableNotFound = new RestError("gone mid-scan", { statusCode: 404, code: "TableNotFound" });
    const iterable = fakeIterable([{ rowKey: "already-fetched" }], tableNotFound);

    await expect(collectEntitiesTolerant(iterable)).resolves.toEqual([{ rowKey: "already-fetched" }]);
  });

  it("NEGATIVE CONTROL — a non-404 RestError (403 AuthorizationFailure) still propagates, not swallowed", async () => {
    const forbidden = new RestError("access denied", { statusCode: 403, code: "AuthorizationFailure" });
    const iterable = fakeIterable<{ rowKey: string }>([], forbidden);

    await expect(collectEntitiesTolerant(iterable)).rejects.toBe(forbidden);
  });

  it("NEGATIVE CONTROL — a 500 still propagates", async () => {
    const serverError = new RestError("internal server error", { statusCode: 500 });
    const iterable = fakeIterable<{ rowKey: string }>([], serverError);

    await expect(collectEntitiesTolerant(iterable)).rejects.toBe(serverError);
  });

  it("NEGATIVE CONTROL — a non-RestError (e.g. a network error) still propagates", async () => {
    const networkError = new Error("ECONNREFUSED");
    const iterable = fakeIterable<{ rowKey: string }>([], networkError);

    await expect(collectEntitiesTolerant(iterable)).rejects.toBe(networkError);
  });
});
