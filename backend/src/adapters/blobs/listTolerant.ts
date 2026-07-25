// specs/002 §4.2 (normative), specs/008 §9 (B20) — mirrors ../tables/listTolerant.ts: a blob
// container that has never been created is indistinguishable, for erasure/read purposes, from
// one that exists and is empty. `listBlobsFlat`/`listBlobsByHierarchy` throw `ContainerNotFound`
// (404) on the first page fetch — every prefix wipe/walk in this directory funnels that
// iterator through `collectBlobsTolerant` so the tolerance lives in one place.
import { RestError } from "@azure/storage-blob";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

/**
 * Drains an async blob-listing iterator into an array. A container that has never been
 * created surfaces `ContainerNotFound` as a 404 on the first page fetch — that resolves to an
 * empty array here. Any other error still propagates; only whatever was already collected
 * before a 404 is returned (never discarded).
 */
export async function collectBlobsTolerant<T>(iterable: AsyncIterable<T>): Promise<T[]> {
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

/**
 * Deletes a single blob, tolerating BOTH the blob itself never having been written
 * (`BlobNotFound`) AND its container never having been created (`ContainerNotFound`).
 * `BlobClient.deleteIfExists()` only swallows the former — a container that was never
 * created (e.g. a family that never set a geofence config) surfaces the latter, which the
 * SDK does NOT treat as "nothing to delete" for that call, so it would otherwise throw
 * uncaught out of an erasure path (B20 — geofenceConfigBlobRepo.deleteConfig).
 */
export async function deleteBlobTolerant(client: { delete(): Promise<unknown> }): Promise<void> {
  try {
    await client.delete();
  } catch (err) {
    if (!isNotFound(err)) throw err;
  }
}
