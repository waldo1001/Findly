// specs/002 §1 — credential selection by endpoint host: the well-known Azurite
// devstoreaccount1 name/key for local emulator hosts, DefaultAzureCredential otherwise.
// No connection strings/keys for the real account — only managed identity.

import { AzureNamedKeyCredential, TableClient } from "@azure/data-tables";
import { DefaultAzureCredential } from "@azure/identity";

// This is Azurite's well-known, publicly-documented emulator key (identical on every
// Azurite install everywhere — see Microsoft's Azurite docs). It is NOT a real account
// credential and only ever talks to 127.0.0.1/localhost.
const AZURITE_ACCOUNT_NAME = "devstoreaccount1";
const AZURITE_ACCOUNT_KEY =
  "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==";

function isLocalEmulatorHost(hostname: string): boolean {
  return hostname === "127.0.0.1" || hostname === "localhost";
}

// B23 (specs/002 §1) — defense-in-depth. Unlike this codebase's blob store (which self-heals
// via create-if-not-exists on every append, specs/002 §3.2), Azure Table Storage does NOT
// auto-create a table on first write. A provisioning gap (a forgotten docs/azure-setup.md step,
// a different deployment path, disaster recovery) previously meant a real storage account with
// zero tables 500'd `TableNotFound` on the very first write to any table — masked on every READ
// path because TableNotFound is a plain 404, already indistinguishable from "row not found" by
// every `isNotFound`/`listTolerant` check (specs/002 §4.2, B20/B22), but writes have no such
// swallow (nor should they). This makes table existence self-healing at this one chokepoint, so
// every one of the 13 table adapters is covered without touching any of them individually.
//
// `TableClient.createTable()` is itself idempotent (verified against @azure/data-tables's own
// implementation — TableClient.js delegates to errorHelpers.js#handleTableAlreadyExists): it
// swallows exactly the 409 "TableAlreadyExists" response and rethrows every other error
// unchanged. That is what makes the concurrent-cold-start race safe — several Function
// instances (separate processes, no shared cache) or several concurrent invocations within one
// instance (before the cache below is warm) can all call createTable() for the same table at
// once, and every one of them succeeds: whoever loses the race simply gets the swallowed 409.
//
// Table names confirmed to exist are cached for the lifetime of this process (module-level —
// there is no existing precedent in this codebase for this exact "check once per process, then
// trust" shape; authGuard.ts's AuthContext, for comparison, is resolved fresh per request) so
// only the FIRST operation against a given table name in this process's life pays for the
// existence check; every later operation is a plain `Set.has` before proceeding straight to the
// real call — no added round trip once warmed.
const confirmedTables = new Set<string>();

// De-dupes concurrent in-flight creations within this process: several operations racing in
// before `confirmedTables` is warm share the ONE underlying createTable() call/promise instead
// of each firing its own. Purely a same-process efficiency optimization — correctness against a
// genuinely different process (which cannot see this map at all) still holds because
// createTable() itself is idempotent (see above).
const pendingCreates = new Map<string, Promise<void>>();

/**
 * Ensures `tableName` exists before the caller proceeds, idempotently, with the per-process
 * caching described above. Transient failures (a network blip, a genuine permission error, …)
 * are never cached as confirmed and evict themselves from `pendingCreates` on rejection, so the
 * very next operation gets to try again from scratch rather than being stuck behind a poisoned
 * cache entry.
 */
async function ensureTableExists(realClient: TableClient, tableName: string): Promise<void> {
  if (confirmedTables.has(tableName)) return;
  let pending = pendingCreates.get(tableName);
  if (!pending) {
    // Not explicitly deleted on the success path — harmless today only because the 13 table
    // names are a small, fixed, hardcoded set (never request-influenced): `confirmedTables.has`
    // short-circuits before this entry is ever consulted again, so it just sits inert for the
    // rest of the process's life. Revisit if table names ever become dynamic/per-tenant.
    pending = realClient.createTable().then(
      () => {
        confirmedTables.add(tableName);
      },
      (err: unknown) => {
        pendingCreates.delete(tableName);
        throw err;
      },
    );
    pendingCreates.set(tableName, pending);
  }
  return pending;
}

/**
 * Wraps the real listEntities() call so the table-existence check runs before the FIRST page
 * fetch (listEntities()/byPage() are both lazy — no network call happens until iteration
 * begins), while still returning a plain, synchronous PagedAsyncIterableIterator so every
 * existing `for await`/`collectEntitiesTolerant` call site is unaffected.
 */
function wrapListEntities(target: TableClient, tableName: string, args: unknown[]) {
  const callReal = () =>
    (
      target.listEntities as (...a: unknown[]) => AsyncIterable<unknown> & { byPage: (s?: unknown) => AsyncIterable<unknown> }
    )(...args);

  async function* iterate() {
    await ensureTableExists(target, tableName);
    yield* callReal();
  }
  async function* iteratePages(settings: unknown) {
    await ensureTableExists(target, tableName);
    yield* callReal().byPage(settings);
  }

  const generator = iterate();
  return {
    next: () => generator.next(),
    [Symbol.asyncIterator]() {
      return this;
    },
    byPage: (settings?: unknown) => iteratePages(settings),
  };
}

/**
 * Wraps a real TableClient so every operation ensures the table exists first (see
 * `ensureTableExists`), transparently to every one of the 13 table-adapter call sites — none of
 * them need to change. `createTable` and `deleteTable` get dedicated handling instead of the
 * generic "ensure, then call" wrapper:
 *  - `createTable` IS the ensure operation — routed straight to `ensureTableExists` rather than
 *    ensure-then-create, which would just be a redundant second round trip.
 *  - `deleteTable` bypasses the ensure step entirely (no reason to create a table immediately
 *    before deleting it) and, once it completes, evicts the table from both caches. In
 *    production no adapter ever calls `deleteTable`; it exists for integration-test fixtures
 *    (`test/integration/support/ensureStorage.ts`'s `dropTables`) that deliberately drop a table
 *    to reproduce the never-created case — without this eviction, a later operation within the
 *    same test process would wrongly trust a stale "confirmed" cache entry for a table that no
 *    longer exists.
 */
// Safety of this Proxy pattern is contingent on TableClient exposing only plain public instance
// fields internally (verified true for @azure/data-tables@13.3.2 — no `#private` fields, no
// accessor properties, so `Reflect.get(target, prop, receiver)` with `receiver` set to the proxy
// is harmless: `receiver` only matters for accessor properties, and every method below is invoked
// via explicit `.apply(target, args)`, never a bare call that would bind `this` to the proxy).
// If a future SDK upgrade introduces private class fields, a method could break when called
// through this wrapper — re-verify this assumption when bumping @azure/data-tables.
function withSelfHealingTable(realClient: TableClient, tableName: string): TableClient {
  const handler: ProxyHandler<TableClient> = {
    get(target, prop, receiver) {
      if (prop === "createTable") {
        return () => ensureTableExists(target, tableName);
      }
      if (prop === "deleteTable") {
        return async (...args: unknown[]) => {
          const original = Reflect.get(target, prop, receiver) as (...a: unknown[]) => Promise<void>;
          const result = await original.apply(target, args);
          confirmedTables.delete(tableName);
          pendingCreates.delete(tableName);
          return result;
        };
      }
      if (prop === "listEntities") {
        return (...args: unknown[]) => wrapListEntities(target, tableName, args);
      }
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== "function") return value;
      return async (...args: unknown[]) => {
        await ensureTableExists(target, tableName);
        return (value as (...a: unknown[]) => unknown).apply(target, args);
      };
    },
  };
  return new Proxy(realClient, handler);
}

export function createTableClient(tableName: string): TableClient {
  const endpoint = process.env.TABLES_ENDPOINT;
  if (!endpoint) {
    throw new Error("TABLES_ENDPOINT app setting is required");
  }
  const host = new URL(endpoint).hostname;
  const client = isLocalEmulatorHost(host)
    ? // Azurite's local endpoint is plain http:// — recent @azure/core-rest-pipeline versions
      // refuse non-TLS requests unless explicitly opted in. Only ever applies on this
      // local-emulator-host branch, never against a real (always-https) Azure account.
      new TableClient(endpoint, tableName, new AzureNamedKeyCredential(AZURITE_ACCOUNT_NAME, AZURITE_ACCOUNT_KEY), {
        allowInsecureConnection: true,
      })
    : new TableClient(endpoint, tableName, new DefaultAzureCredential());
  return withSelfHealingTable(client, tableName);
}
