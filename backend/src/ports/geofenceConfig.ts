// specs/001 §7.1/§7.2 — geofence config document (read + full-document replace),
// specs/002 §3.1/§3.4 (the `config` container, one block blob per family, the blob's ETag
// IS the API ETag). B2 only needed `getEtag` (the §5.1 piggyback seam); B5 completes the
// port with the full read/write flow.

export interface GeofenceEntry {
  geofenceId: string;
  name: string;
  lat: number;
  lon: number;
  radiusM: number;
  /** Free string ≤ 30, client-rendered (§7.1). */
  icon: string;
  notifyOnEnter: boolean;
  notifyOnExit: boolean;
}

export interface GeofenceConfigDocument {
  version: number;
  geofences: GeofenceEntry[];
}

export interface GeofenceConfigWithEtag {
  config: GeofenceConfigDocument;
  etag: string;
}

export type ReplaceGeofenceConfigOutcome =
  | { outcome: "ok"; etag: string }
  /** If-Match/If-None-Match:* mismatch — storage 412 (002 §3.4). Never thrown, so the
   * domain can map it to 409 GEOFENCE_VERSION_CONFLICT with `details.currentEtag`. */
  | { outcome: "conflict"; currentEtag: string };

export interface GeofenceConfigRepo {
  /** Current config blob ETag for the family, or "0" when no config exists yet (001 §7.1). */
  getEtag(familyId: string): Promise<string>;
  /** Full document + ETag read (§7.1). A never-written family reads back as the documented
   * empty default: `{version: 0, geofences: []}` with etag `"0"`. */
  get(familyId: string): Promise<GeofenceConfigWithEtag>;
  /**
   * Full-document replace with optimistic concurrency (002 §3.4). `ifMatch` is the client's
   * `If-Match` header value verbatim, including the documented `"0"` sentinel for the very
   * first write — the adapter is responsible for translating `"0"` into an
   * `If-None-Match: *` (create-only) condition and any other value into `If-Match: <etag>`.
   */
  replace(
    familyId: string,
    document: GeofenceConfigDocument,
    ifMatch: string,
  ): Promise<ReplaceGeofenceConfigOutcome>;
  /** Deletes the `config/{familyId}/geofences.json` blob — family deletion (001 §13.3, 002
   * §4.2 step 4, B19). Idempotent. */
  deleteConfig(familyId: string): Promise<void>;
}
