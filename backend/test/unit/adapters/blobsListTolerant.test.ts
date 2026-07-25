// specs/002 §4.2 (normative), specs/008 §9 (B20) — unit coverage for the shared helpers every
// blob adapter's prefix wipe/walk now funnels through (src/adapters/blobs/listTolerant.ts).
// Pure logic, no Azure SDK network calls — fast, no Azurite required (CLAUDE.md: `npm test`
// must never require Azurite). The critical case here is the NEGATIVE CONTROL: a genuine
// non-404 storage error (403/500) must still propagate, proving the fix doesn't over-swallow.

import { describe, expect, it } from "vitest";
import { RestError } from "@azure/storage-blob";
import { collectBlobsTolerant, deleteBlobTolerant } from "../../../src/adapters/blobs/listTolerant";

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

describe("unit/adapters/blobs/listTolerant — collectBlobsTolerant (specs/002 §4.2, 008 §9, B20)", () => {
  it("drains a normal blob-listing iterator into an array", async () => {
    const iterable = fakeIterable([{ name: "a" }, { name: "b" }]);

    await expect(collectBlobsTolerant(iterable)).resolves.toEqual([{ name: "a" }, { name: "b" }]);
  });

  it("resolves to an empty array when the container has never been created (ContainerNotFound, 404)", async () => {
    const containerNotFound = new RestError("The specified container does not exist.", {
      statusCode: 404,
      code: "ContainerNotFound",
    });
    const iterable = fakeIterable<{ name: string }>([], containerNotFound);

    await expect(collectBlobsTolerant(iterable)).resolves.toEqual([]);
  });

  it("does not discard blobs already collected before a 404 arrives on a later page", async () => {
    const containerNotFound = new RestError("gone mid-scan", { statusCode: 404, code: "ContainerNotFound" });
    const iterable = fakeIterable([{ name: "already-fetched" }], containerNotFound);

    await expect(collectBlobsTolerant(iterable)).resolves.toEqual([{ name: "already-fetched" }]);
  });

  it("NEGATIVE CONTROL — a non-404 RestError (403 AuthorizationFailure) still propagates, not swallowed", async () => {
    const forbidden = new RestError("access denied", { statusCode: 403, code: "AuthorizationFailure" });
    const iterable = fakeIterable<{ name: string }>([], forbidden);

    await expect(collectBlobsTolerant(iterable)).rejects.toBe(forbidden);
  });

  it("NEGATIVE CONTROL — a 500 still propagates", async () => {
    const serverError = new RestError("internal server error", { statusCode: 500 });
    const iterable = fakeIterable<{ name: string }>([], serverError);

    await expect(collectBlobsTolerant(iterable)).rejects.toBe(serverError);
  });
});

describe("unit/adapters/blobs/listTolerant — deleteBlobTolerant (specs/002 §4.2, 008 §9, B20)", () => {
  it("resolves when the delete succeeds", async () => {
    let called = false;
    const client = {
      async delete(): Promise<unknown> {
        called = true;
        return {};
      },
    };

    await expect(deleteBlobTolerant(client)).resolves.toBeUndefined();
    expect(called).toBe(true);
  });

  it("swallows BlobNotFound (the blob itself was never written)", async () => {
    const client = {
      async delete(): Promise<unknown> {
        throw new RestError("The specified blob does not exist.", { statusCode: 404, code: "BlobNotFound" });
      },
    };

    await expect(deleteBlobTolerant(client)).resolves.toBeUndefined();
  });

  it("swallows ContainerNotFound — the exact gap BlobClient.deleteIfExists() alone does NOT cover (B20, geofenceConfigBlobRepo)", async () => {
    const client = {
      async delete(): Promise<unknown> {
        throw new RestError("The specified container does not exist.", { statusCode: 404, code: "ContainerNotFound" });
      },
    };

    await expect(deleteBlobTolerant(client)).resolves.toBeUndefined();
  });

  it("NEGATIVE CONTROL — a non-404 error (403) still propagates, not swallowed", async () => {
    const forbidden = new RestError("access denied", { statusCode: 403, code: "AuthorizationFailure" });
    const client = {
      async delete(): Promise<unknown> {
        throw forbidden;
      },
    };

    await expect(deleteBlobTolerant(client)).rejects.toBe(forbidden);
  });
});
