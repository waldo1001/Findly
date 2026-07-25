// B23 (specs/002 §1) — defense-in-depth fix for the live production incident: `stfindly` (the
// real storage account) had zero Table Storage tables, so `POST /families` (and every other
// write endpoint) 500'd with `TableNotFound`. Azure Table Storage does NOT auto-create a table
// on first write (unlike this codebase's blob store, which already self-heals via
// create-if-not-exists on append, specs/002 §3.2) — `createTableClient`
// (backend/src/adapters/tables/tableClientFactory.ts) only ever pointed a `TableClient` at a
// table name, never created it. This file proves the fix directly against real Azurite: no
// in-memory fake has any concept of a missing table at all (test/fakes/), so this class of bug
// is invisible to unit tests.
//
// Requires Azurite (`npm run dev:storage`); run via `npm run test:integration`. Runs with
// `fileParallelism: false` (vitest.integration.config.ts) — this file drops tables that OTHER
// integration test files' `beforeAll` hooks also depend on existing.

import { beforeAll, describe, expect, it } from "vitest";
import { TableClient } from "@azure/data-tables";
import { createTableClient } from "../../src/adapters/tables/tableClientFactory";
import { dropTables, ensureTables } from "./support/ensureStorage";
import { testUserId } from "./support/ids";

describe("integration/tableClientFactory self-healing table creation (specs/002 §1, B23)", () => {
  const TABLE_NAME = "B23SelfHealTest";

  beforeAll(async () => {
    // Universe of tables this file touches. Ensured up front so other files' shared Azurite
    // state is never left worse than it found it, mirroring erasureMissingStorage.test.ts.
    await ensureTables(TABLE_NAME);
  }, 30_000);

  describe("the exact repro: a write against a never-created table", () => {
    it("createEntity succeeds instead of throwing TableNotFound, for a table that has never been created", async () => {
      await dropTables(TABLE_NAME);
      const client = createTableClient(TABLE_NAME);

      await expect(
        client.createEntity({ partitionKey: testUserId(), rowKey: "row", value: 1 }),
      ).resolves.not.toThrow();

      await ensureTables(TABLE_NAME);
    });
  });

  describe("idempotent when the table already exists", () => {
    it("createEntity against an already-provisioned table behaves exactly as before — no error, no behavior change", async () => {
      const client = createTableClient(TABLE_NAME);
      const partitionKey = testUserId();

      await expect(client.createEntity({ partitionKey, rowKey: "row", value: 2 })).resolves.not.toThrow();
      const stored = await client.getEntity(partitionKey, "row");
      expect(stored.value).toBe(2);
    });
  });

  describe("caching: the create-if-not-exists check does not re-run once a table is confirmed", () => {
    it("a second operation against the same table name does not re-issue the underlying createTable call", async () => {
      const tableName = "B23CacheTest";
      await dropTables(tableName);
      let createTableCalls = 0;
      const original = TableClient.prototype.createTable;
      // Monkeypatches the SDK prototype method itself (shared by every TableClient instance,
      // including ones our factory constructs internally) so this test can prove the caching
      // behavior from OUTSIDE tableClientFactory.ts's own internals, without reimplementing —
      // or over-mocking — the module under test.
      TableClient.prototype.createTable = function (this: TableClient, ...args: unknown[]) {
        createTableCalls += 1;
        return (original as (...a: unknown[]) => Promise<void>).apply(this, args);
      };

      try {
        const clientA = createTableClient(tableName);
        await clientA.createEntity({ partitionKey: testUserId(), rowKey: "row", value: 1 });
        expect(createTableCalls).toBe(1);

        // A brand-new client instance for the SAME table name — the cache is keyed by table
        // name at module scope, not by client instance, matching how 13 different adapters
        // each construct their own client for a table that may already be confirmed.
        const clientB = createTableClient(tableName);
        await clientB.createEntity({ partitionKey: testUserId(), rowKey: "row2", value: 2 });
        expect(createTableCalls).toBe(1);
      } finally {
        TableClient.prototype.createTable = original;
      }

      await ensureTables(tableName);
    });
  });

  describe("concurrent race: multiple operations against a never-created table, fired before any cache entry exists", () => {
    it("all concurrent operations succeed cleanly — no TableNotFound and no leaked TableAlreadyExists conflict", async () => {
      const tableName = "B23RaceTest";
      await dropTables(tableName);
      const client = createTableClient(tableName);

      const results = await Promise.allSettled(
        Array.from({ length: 10 }, (_, i) => client.createEntity({ partitionKey: testUserId(), rowKey: `row${i}`, value: i })),
      );

      const rejected = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
      expect(rejected).toEqual([]);
      expect(results.every((r) => r.status === "fulfilled")).toBe(true);

      await ensureTables(tableName);
    });
  });
});
