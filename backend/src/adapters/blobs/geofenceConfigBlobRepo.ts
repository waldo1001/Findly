// specs/002 §3.1/§3.4, specs/001 §7.1/§7.2 — the `config` block blob: full document
// read/write with optimistic concurrency (the blob's ETag IS the API ETag). Integration
// tested against Azurite (test/integration/); no unit tests here (thin adapter, excluded
// from mutation, per backend/README.md) — the pure business logic (version bump,
// role/limit/uniqueness validation, GEOFENCE_VERSION_CONFLICT mapping) lives in
// src/domain/geofence/*.

import { RestError } from "@azure/storage-blob";
import { createContainerClient } from "./blobClientFactory";
import { deleteBlobTolerant } from "./listTolerant";
import type {
  GeofenceConfigDocument,
  GeofenceConfigRepo,
  GeofenceConfigWithEtag,
  ReplaceGeofenceConfigOutcome,
} from "../../ports/geofenceConfig";

const CONFIG_CONTAINER = "config";
const NO_CONFIG_ETAG = "0";
const EMPTY_CONFIG: GeofenceConfigDocument = { version: 0, geofences: [] };

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

/**
 * A rejected conditional write (002 §3.4): `If-Match: <etag>` mismatch surfaces as `412
 * ConditionNotMet`, but `If-None-Match: *` on an already-existing blob (the "0" sentinel
 * racing a completed first write) surfaces as `409 BlobAlreadyExists` instead — Azure Blob
 * Storage uses a different status for "create-only, but it already exists" than for "update,
 * but the ETag moved." Both are the same "someone else won the race" outcome for our purposes.
 */
function isConditionalWriteConflict(err: unknown): boolean {
  if (!(err instanceof RestError)) return false;
  if (err.statusCode === 412) return true;
  return err.statusCode === 409 && err.code === "BlobAlreadyExists";
}

export class BlobGeofenceConfigRepo implements GeofenceConfigRepo {
  private readonly container = createContainerClient(CONFIG_CONTAINER);

  private blobPath(familyId: string): string {
    return `${familyId}/geofences.json`;
  }

  async getEtag(familyId: string): Promise<string> {
    const client = this.container.getBlockBlobClient(this.blobPath(familyId));
    try {
      const props = await client.getProperties();
      return props.etag ?? NO_CONFIG_ETAG;
    } catch (err) {
      if (isNotFound(err)) return NO_CONFIG_ETAG;
      throw err;
    }
  }

  async get(familyId: string): Promise<GeofenceConfigWithEtag> {
    const client = this.container.getBlockBlobClient(this.blobPath(familyId));
    try {
      const [buffer, props] = await Promise.all([client.downloadToBuffer(), client.getProperties()]);
      const config = JSON.parse(buffer.toString("utf-8")) as GeofenceConfigDocument;
      return { config, etag: props.etag ?? NO_CONFIG_ETAG };
    } catch (err) {
      if (isNotFound(err)) {
        return { config: EMPTY_CONFIG, etag: NO_CONFIG_ETAG };
      }
      throw err;
    }
  }

  /**
   * `ifMatch === "0"` (the documented first-write sentinel, 001 §7.2) uploads with
   * `If-None-Match: *` (create-only); any other value uploads with `If-Match: <etag>`. A
   * storage `412` (precondition failed — someone else already wrote first) resolves to a
   * `conflict` outcome carrying the actual current ETag, never a thrown error (002 §3.4) —
   * the domain maps that to `409 GEOFENCE_VERSION_CONFLICT`.
   */
  async replace(
    familyId: string,
    document: GeofenceConfigDocument,
    ifMatch: string,
  ): Promise<ReplaceGeofenceConfigOutcome> {
    const client = this.container.getBlockBlobClient(this.blobPath(familyId));
    const body = Buffer.from(JSON.stringify(document), "utf-8");
    const conditions = ifMatch === NO_CONFIG_ETAG ? { ifNoneMatch: "*" } : { ifMatch };
    try {
      const result = await client.upload(body, body.length, { conditions });
      return { outcome: "ok", etag: result.etag ?? NO_CONFIG_ETAG };
    } catch (err) {
      if (isConditionalWriteConflict(err)) {
        const currentEtag = await this.getEtag(familyId);
        return { outcome: "conflict", currentEtag };
      }
      throw err;
    }
  }

  /** Idempotent (002 §4.2 step 4 — family deletion, B19). Tolerates the `config` container
   * never having been created at all (a family that never set a geofence config, B20):
   * `deleteIfExists()` alone only swallows `BlobNotFound`, NOT `ContainerNotFound`, so a
   * missing container needs the extra tolerance `deleteBlobTolerant` provides. */
  async deleteConfig(familyId: string): Promise<void> {
    const client = this.container.getBlockBlobClient(this.blobPath(familyId));
    await deleteBlobTolerant(client);
  }
}
