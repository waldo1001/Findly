import type {
  GeofenceConfigDocument,
  GeofenceConfigRepo,
  GeofenceConfigWithEtag,
  ReplaceGeofenceConfigOutcome,
} from "../../src/ports/geofenceConfig";

const NO_CONFIG_ETAG = "0";
const EMPTY_CONFIG: GeofenceConfigDocument = { version: 0, geofences: [] };

interface StoredConfig {
  config: GeofenceConfigDocument;
  etag: string;
}

export class InMemoryGeofenceConfigRepo implements GeofenceConfigRepo {
  private readonly configs = new Map<string, StoredConfig>();
  private nextEtagSeq = 1;

  /** Test seam: seed just the ETag (B2 §5.1 piggyback tests) without a full document. */
  seed(familyId: string, etag: string): void {
    const existing = this.configs.get(familyId);
    this.configs.set(familyId, { config: existing ? existing.config : EMPTY_CONFIG, etag });
  }

  /** Test seam: seed a full config document + its ETag (B5). */
  seedConfig(familyId: string, config: GeofenceConfigDocument, etag: string): void {
    this.configs.set(familyId, { config: { version: config.version, geofences: [...config.geofences] }, etag });
  }

  async getEtag(familyId: string): Promise<string> {
    return this.configs.get(familyId)?.etag ?? NO_CONFIG_ETAG;
  }

  async get(familyId: string): Promise<GeofenceConfigWithEtag> {
    const stored = this.configs.get(familyId);
    if (!stored) {
      return { config: { version: EMPTY_CONFIG.version, geofences: [] }, etag: NO_CONFIG_ETAG };
    }
    return {
      config: { version: stored.config.version, geofences: [...stored.config.geofences] },
      etag: stored.etag,
    };
  }

  async replace(
    familyId: string,
    document: GeofenceConfigDocument,
    ifMatch: string,
  ): Promise<ReplaceGeofenceConfigOutcome> {
    const stored = this.configs.get(familyId);
    const currentEtag = stored?.etag ?? NO_CONFIG_ETAG;
    if (ifMatch !== currentEtag) {
      return { outcome: "conflict", currentEtag };
    }
    const newEtag = `"fake-etag-${this.nextEtagSeq++}"`;
    this.configs.set(familyId, {
      config: { version: document.version, geofences: [...document.geofences] },
      etag: newEtag,
    });
    return { outcome: "ok", etag: newEtag };
  }

  async deleteConfig(familyId: string): Promise<void> {
    this.configs.delete(familyId);
  }
}
