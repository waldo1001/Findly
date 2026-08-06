// B25 (specs/002 §1, §3) — defense-in-depth fix for the live production incident: `stfindly`
// (the real storage account) had zero application blob containers, so `POST /locations`
// (history append) and `PUT /geofences` both 500'd with `ContainerNotFound` for every family
// from first deploy until the containers were created by hand on 2026-08-06. specs/002 §1's
// B23 note used to claim "this codebase's blob store self-heals via create-if-not-exists on
// append (§3.2)" — that was FALSE: §3.2's create-if-not-exists operates on the BLOB (the
// per-day append blob), never on the CONTAINER, and `createContainerClient`
// (backend/src/adapters/blobs/blobClientFactory.ts) only ever pointed a `ContainerClient` at a
// container name, never created it. Corrected in specs/002 §1 (f7c7452).
//
// This file proves the fix directly against real Azurite, the same way B23's
// tableClientFactorySelfHealing.test.ts did for tables. It deliberately does NOT rely on
// Azurite's own implicit-create-on-write behaviour to pass: every `it` below drops the
// container FIRST via `dropContainers` (real Azure DELETE), then asserts the write succeeds
// anyway — so a naive assertion that would also pass against Azurite's auto-create (or against
// the pre-fix code, which never observes ContainerNotFound because Azurite never raises it
// without an explicit drop) cannot slip through here. No in-memory fake has any concept of a
// missing container at all (test/fakes/), so this class of bug is invisible to unit tests.
//
// Requires Azurite (`npm run dev:storage`); run via `npm run test:integration`. Runs with
// `fileParallelism: false` (vitest.integration.config.ts) — this file drops containers that
// OTHER integration test files' `beforeAll` hooks also depend on existing.

import { beforeAll, describe, expect, it } from "vitest";
import { ContainerClient } from "@azure/storage-blob";
import { createContainerClient } from "../../src/adapters/blobs/blobClientFactory";
import { dropContainers, ensureContainers } from "./support/ensureStorage";

describe("integration/blobClientFactory self-healing container creation (specs/002 §1/§3, B25)", () => {
  const CONTAINER_NAME = "b25selfhealtest";

  beforeAll(async () => {
    // Universe of containers this file touches. Ensured up front so other files' shared
    // Azurite state is never left worse than it found it, mirroring
    // tableClientFactorySelfHealing.test.ts / erasureMissingStorage.test.ts.
    await ensureContainers(CONTAINER_NAME);
  }, 30_000);

  describe("the exact repro: a write against a never-created container", () => {
    it("AppendBlobClient.create succeeds instead of throwing ContainerNotFound, for a container that has never been created", async () => {
      await dropContainers(CONTAINER_NAME);
      const container = createContainerClient(CONTAINER_NAME);
      const blob = container.getAppendBlobClient("repro/append-target.jsonl");

      await expect(blob.create({ conditions: { ifNoneMatch: "*" } })).resolves.not.toThrow();

      await ensureContainers(CONTAINER_NAME);
    });

    it("BlockBlobClient.upload succeeds instead of throwing ContainerNotFound, mirroring BlobGeofenceConfigRepo.replace's first write (002 §3.4)", async () => {
      await dropContainers(CONTAINER_NAME);
      const container = createContainerClient(CONTAINER_NAME);
      const blob = container.getBlockBlobClient("repro/config.json");
      const body = Buffer.from(JSON.stringify({ version: 1 }), "utf-8");

      await expect(
        blob.upload(body, body.length, { conditions: { ifNoneMatch: "*" } }),
      ).resolves.not.toThrow();

      await ensureContainers(CONTAINER_NAME);
    });
  });

  describe("idempotent when the container already exists", () => {
    it("AppendBlobClient.create against an already-provisioned container behaves exactly as before — no error, no behavior change", async () => {
      const container = createContainerClient(CONTAINER_NAME);
      const blob = container.getAppendBlobClient("repro/already-exists.jsonl");

      await expect(blob.create({ conditions: { ifNoneMatch: "*" } })).resolves.not.toThrow();
      const buffer = Buffer.from("x", "utf-8");
      await blob.appendBlock(buffer, buffer.length);

      const downloaded = await blob.downloadToBuffer();
      expect(downloaded.toString("utf-8")).toBe("x");
    });
  });

  describe("caching: the create-if-not-exists check does not re-run once a container is confirmed", () => {
    it("a second operation against the same container name does not re-issue the underlying createIfNotExists call", async () => {
      const containerName = "b25cachetest";
      await dropContainers(containerName);
      let createCalls = 0;
      const original = ContainerClient.prototype.createIfNotExists;
      // Monkeypatches the SDK prototype method itself (shared by every ContainerClient
      // instance, including ones our factory constructs internally) so this test can prove
      // the caching behavior from OUTSIDE blobClientFactory.ts's own internals, without
      // reimplementing — or over-mocking — the module under test. Mirrors
      // tableClientFactorySelfHealing.test.ts's TableClient.prototype.createTable patch.
      ContainerClient.prototype.createIfNotExists = function (this: ContainerClient, ...args: unknown[]) {
        createCalls += 1;
        return (original as (...a: unknown[]) => Promise<unknown>).apply(this, args);
      };

      try {
        const containerA = createContainerClient(containerName);
        const blobA = containerA.getAppendBlobClient("cache/one.jsonl");
        await blobA.create({ conditions: { ifNoneMatch: "*" } });
        expect(createCalls).toBe(1);

        // A brand-new client instance for the SAME container name — the cache is keyed by
        // container name at module scope, not by client instance, matching how the `config`/
        // `history`/`events` adapters each construct their own client that may already be
        // confirmed by an earlier operation in this process.
        const containerB = createContainerClient(containerName);
        const blobB = containerB.getAppendBlobClient("cache/two.jsonl");
        await blobB.create({ conditions: { ifNoneMatch: "*" } });
        expect(createCalls).toBe(1);
      } finally {
        ContainerClient.prototype.createIfNotExists = original;
      }

      await ensureContainers(containerName);
    });
  });

  describe("concurrent race: multiple operations against a never-created container, fired before any cache entry exists", () => {
    it("all concurrent operations succeed cleanly — no ContainerNotFound and no leaked ContainerAlreadyExists conflict", async () => {
      const containerName = "b25racetest";
      await dropContainers(containerName);
      const container = createContainerClient(containerName);

      const results = await Promise.allSettled(
        Array.from({ length: 10 }, (_, i) => {
          const blob = container.getAppendBlobClient(`race/blob-${i}.jsonl`);
          return blob.create({ conditions: { ifNoneMatch: "*" } });
        }),
      );

      const rejected = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
      expect(rejected).toEqual([]);
      expect(results.every((r) => r.status === "fulfilled")).toBe(true);

      await ensureContainers(containerName);
    });
  });
});
