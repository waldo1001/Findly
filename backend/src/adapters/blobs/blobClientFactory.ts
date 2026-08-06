// specs/002 §1 — credential selection by endpoint host: the well-known Azurite
// devstoreaccount1 name/key for local emulator hosts, DefaultAzureCredential otherwise.
// No connection strings/keys for the real account — only managed identity.

import { BlobServiceClient, ContainerClient, StorageSharedKeyCredential } from "@azure/storage-blob";
import { DefaultAzureCredential } from "@azure/identity";

// Azurite's well-known, publicly-documented emulator key (identical on every Azurite
// install everywhere — see Microsoft's Azurite docs). Not a real account credential;
// only ever talks to 127.0.0.1/localhost (mirrors tableClientFactory.ts).
const AZURITE_ACCOUNT_NAME = "devstoreaccount1";
const AZURITE_ACCOUNT_KEY =
  "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==";

function isLocalEmulatorHost(hostname: string): boolean {
  return hostname === "127.0.0.1" || hostname === "localhost";
}

// B25 (specs/002 §1, §3) — defense-in-depth, mirroring tableClientFactory.ts's B23 fix for
// tables. specs/002 §1 USED to claim this codebase's blob store already self-healed via
// create-if-not-exists "on append" (§3.2) — that was false: §3.2's create-if-not-exists
// operates on the BLOB (the per-day append blob / the config block blob), never on the
// CONTAINER, and nothing anywhere ever created `config`/`history`/`events`. A real storage
// account provisioned with zero containers 500'd `ContainerNotFound` on the very first write
// to any of them — this is the live production incident (2026-08-06): `POST /locations` and
// `PUT /geofences` failed for every family from first deploy until the containers were
// created by hand. Corrected in specs/002 §1 (f7c7452).
//
// Same idiom as `withSelfHealingTable`: `ContainerClient.createIfNotExists()` is itself
// idempotent (verified against @azure/storage-blob@12.26's own source —
// ContainerClient.js#createIfNotExists swallows exactly the 409 "ContainerAlreadyExists"
// response and rethrows every other error unchanged), so several Function instances or
// several concurrent invocations within one instance racing to create the same container all
// succeed — whoever loses the race simply gets the swallowed 409.
//
// Container names confirmed to exist are cached for the lifetime of this process (module-level,
// same "check once per process, then trust" shape as tableClientFactory.ts), so only the FIRST
// operation against a given container name in this process's life pays for the existence
// check; every later operation is a plain `Set.has` before proceeding straight to the real call.
const confirmedContainers = new Set<string>();

// De-dupes concurrent in-flight creations within this process — mirrors tableClientFactory.ts's
// `pendingCreates`. Correctness against a genuinely different process still holds because
// `createIfNotExists()` itself is idempotent (see above); this is purely a same-process
// efficiency optimization.
const pendingCreates = new Map<string, Promise<void>>();

/**
 * Ensures `containerName` exists before the caller proceeds, idempotently, with the
 * per-process caching described above. Transient failures are never cached as confirmed and
 * evict themselves from `pendingCreates` on rejection, so the very next operation gets to try
 * again from scratch rather than being stuck behind a poisoned cache entry.
 */
async function ensureContainerExists(realClient: ContainerClient, containerName: string): Promise<void> {
  if (confirmedContainers.has(containerName)) return;
  let pending = pendingCreates.get(containerName);
  if (!pending) {
    pending = realClient.createIfNotExists().then(
      () => {
        confirmedContainers.add(containerName);
      },
      (err: unknown) => {
        pendingCreates.delete(containerName);
        throw err;
      },
    );
    pendingCreates.set(containerName, pending);
  }
  return pending;
}

/**
 * Wraps a blob-level sub-client (`AppendBlobClient`/`BlockBlobClient`/`BlobClient`, obtained
 * from `container.get*Client(...)`) so every one of ITS operations ensures the container
 * exists first. This is where the actual writes/reads our adapters issue live — unlike
 * `TableClient`, where every operation is a direct method on the one client object,
 * `ContainerClient`'s own methods only ever construct these sub-clients synchronously (no
 * network call); the real `create`/`upload`/`download`/`appendBlock`/... calls happen on the
 * sub-client returned here.
 */
function wrapSubClientWithEnsure<T extends object>(subClient: T, container: ContainerClient, containerName: string): T {
  const handler: ProxyHandler<T> = {
    get(target, prop, receiver) {
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== "function") return value;
      return async (...args: unknown[]) => {
        await ensureContainerExists(container, containerName);
        return (value as (...a: unknown[]) => unknown).apply(target, args);
      };
    },
  };
  return new Proxy(subClient, handler);
}

/**
 * Wraps the real `listBlobsFlat`/`listBlobsByHierarchy` call so the container-existence check
 * runs before the FIRST page fetch (both are lazy — no network call happens until iteration
 * begins), mirroring tableClientFactory.ts's `wrapListEntities`. A container that has never
 * been created still resolves to an empty listing either way (`listTolerant.ts` already
 * swallows `ContainerNotFound`) — this just means the container also gets created as a side
 * effect of listing it, same as every other operation funneled through this factory.
 */
function wrapListBlobs(
  target: ContainerClient,
  containerName: string,
  methodName: "listBlobsFlat" | "listBlobsByHierarchy",
  args: unknown[],
) {
  const callReal = () =>
    (target[methodName] as (...a: unknown[]) => AsyncIterable<unknown> & { byPage: (s?: unknown) => AsyncIterable<unknown> })(
      ...args,
    );

  async function* iterate() {
    await ensureContainerExists(target, containerName);
    yield* callReal();
  }
  async function* iteratePages(settings: unknown) {
    await ensureContainerExists(target, containerName);
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

const BLOB_SUBCLIENT_GETTERS = new Set(["getAppendBlobClient", "getBlockBlobClient", "getBlobClient", "getPageBlobClient"]);
const LIST_METHODS = new Set(["listBlobsFlat", "listBlobsByHierarchy"]);

/**
 * Wraps a real `ContainerClient` so every operation reachable through it ensures the
 * container exists first, transparently to every blob-adapter call site — none of them need
 * to change. Mirrors tableClientFactory.ts's `withSelfHealingTable`:
 *  - `getAppendBlobClient`/`getBlockBlobClient`/`getBlobClient`/`getPageBlobClient` return a
 *    sub-client (see `wrapSubClientWithEnsure`) rather than the raw one — this is where the
 *    adapters' actual writes/reads happen.
 *  - `listBlobsFlat`/`listBlobsByHierarchy` get dedicated lazy-iterator handling
 *    (`wrapListBlobs`), same reason as the table factory's `listEntities`.
 *  - `create`/`createIfNotExists` ARE the ensure operation — routed straight to
 *    `ensureContainerExists` rather than ensure-then-create, which would just be a redundant
 *    second round trip.
 *  - `delete`/`deleteIfExists` bypass the ensure step entirely (no reason to create a
 *    container immediately before deleting it) and, once complete, evict the container from
 *    both caches — exists for integration-test fixtures (`test/integration/support/
 *    ensureStorage.ts`'s `dropContainers`) that deliberately drop a container to reproduce the
 *    never-created case; without this eviction a later operation within the same test process
 *    would wrongly trust a stale "confirmed" cache entry for a container that no longer exists.
 *
 * Safety of this Proxy pattern is contingent on `ContainerClient`/its sub-clients exposing only
 * plain public instance fields internally (verified true for @azure/storage-blob@12.26 — no
 * `#private` fields), same caveat as tableClientFactory.ts's equivalent comment.
 */
function withSelfHealingContainer(realClient: ContainerClient, containerName: string): ContainerClient {
  const handler: ProxyHandler<ContainerClient> = {
    get(target, prop, receiver) {
      if (prop === "create" || prop === "createIfNotExists") {
        return () => ensureContainerExists(target, containerName);
      }
      if (prop === "delete" || prop === "deleteIfExists") {
        return async (...args: unknown[]) => {
          const original = Reflect.get(target, prop, receiver) as (...a: unknown[]) => Promise<unknown>;
          const result = await original.apply(target, args);
          confirmedContainers.delete(containerName);
          pendingCreates.delete(containerName);
          return result;
        };
      }
      if (typeof prop === "string" && BLOB_SUBCLIENT_GETTERS.has(prop)) {
        return (...args: unknown[]) => {
          const original = Reflect.get(target, prop, receiver) as (...a: unknown[]) => object;
          const subClient = original.apply(target, args);
          return wrapSubClientWithEnsure(subClient, target, containerName);
        };
      }
      if (typeof prop === "string" && LIST_METHODS.has(prop)) {
        return (...args: unknown[]) => wrapListBlobs(target, containerName, prop as "listBlobsFlat" | "listBlobsByHierarchy", args);
      }
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== "function") return value;
      return async (...args: unknown[]) => {
        await ensureContainerExists(target, containerName);
        return (value as (...a: unknown[]) => unknown).apply(target, args);
      };
    },
  };
  return new Proxy(realClient, handler);
}

export function createContainerClient(containerName: string): ContainerClient {
  const endpoint = process.env.BLOB_ENDPOINT;
  if (!endpoint) {
    throw new Error("BLOB_ENDPOINT app setting is required");
  }
  const host = new URL(endpoint).hostname;
  const serviceClient = isLocalEmulatorHost(host)
    ? new BlobServiceClient(endpoint, new StorageSharedKeyCredential(AZURITE_ACCOUNT_NAME, AZURITE_ACCOUNT_KEY))
    : new BlobServiceClient(endpoint, new DefaultAzureCredential());
  const client = serviceClient.getContainerClient(containerName);
  return withSelfHealingContainer(client, containerName);
}
