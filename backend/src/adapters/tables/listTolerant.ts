// specs/002 §4.2 (normative), specs/008 §9 (B20) — "not-found" includes the table itself
// never having been created: tables in this design are created lazily by their first write
// (or, on a real account, once by the one-time provisioning in docs/azure-setup.md), so an
// erasure/read can legitimately run against a table that does not exist at all. That is
// indistinguishable, for these purposes, from the table existing and being empty.
//
// This matters specifically for the *list/enumerate* step: every partition/prefix wipe in
// this directory is list-then-delete, and it is the LISTING of a never-created table
// (Azure `TableNotFound`, surfaced as a 404 on the first page fetch) that throws first — the
// per-row delete's own not-found tolerance (the `isNotFound` idiom already used throughout
// this directory for point reads/deletes) never gets a chance to help. This was the exact
// live production bug: `DELETE /users/me`'s first step, `DeviceRepo.listDevices`, threw
// TableNotFound against a storage account with zero application tables.
//
// Every adapter method that lists entities funnels its `listEntities()` iterator through this
// one helper so the tolerance lives in a single place instead of being reimplemented (or
// forgotten) per call site.
import { RestError } from "@azure/data-tables";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

/**
 * Drains an async entity iterator (e.g. `TableClient.listEntities()`) into an array. A table
 * that has never been created surfaces `TableNotFound` as a 404 on the very first page fetch
 * — that resolves to an empty array here, exactly as if the table existed and simply had no
 * matching rows. Any other error (403, 500, a genuine mid-scan failure, ...) still propagates
 * unchanged; only a 404 is swallowed, and only whatever was already collected before it is
 * returned (never discarded) so a 404 arriving after some real pages doesn't lose rows.
 */
export async function collectEntitiesTolerant<T>(iterable: AsyncIterable<T>): Promise<T[]> {
  const items: T[] = [];
  try {
    for await (const item of iterable) {
      items.push(item);
    }
  } catch (err) {
    if (isNotFound(err)) return items;
    throw err;
  }
  return items;
}
