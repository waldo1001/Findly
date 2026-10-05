/**
 * Builders for App Store Connect response documents, shaped like the real API (JSON:API envelopes,
 * `type`/`id`/`attributes`/`relationships`/`links`). Shapes follow Apple's documentation for
 * GET /v1/builds, GET /v1/apps/{id}/appStoreVersions, GET /v1/appStoreVersions/{id}/…,
 * GET /v1/reviewSubmissions and GET /v1/reviewSubmissions/{id}/items.
 */

export const APP_ID = "6797994768";
export const API = "https://api.appstoreconnect.apple.com";

export interface BuildFx {
  id: string;
  /** CFBundleVersion (the build number). */
  buildNumber: string;
  /** Marketing version (CFBundleShortVersionString). `undefined` => the preReleaseVersion is not included. */
  marketingVersion?: string;
  uploadedDate?: string;
  processingState?: string;
}

export function buildsDoc(builds: BuildFx[]) {
  const included = builds
    .filter((b) => b.marketingVersion !== undefined)
    .map((b) => ({
      type: "preReleaseVersions",
      id: `pre-${b.marketingVersion}`,
      attributes: { version: b.marketingVersion, platform: "IOS" },
      links: { self: `${API}/v1/preReleaseVersions/pre-${b.marketingVersion}` },
    }));
  return {
    data: builds.map((b) => ({
      type: "builds",
      id: b.id,
      attributes: {
        version: b.buildNumber,
        uploadedDate: b.uploadedDate ?? "2026-10-05T09:12:00-07:00",
        expirationDate: "2027-01-03T09:12:00-08:00",
        expired: false,
        minOsVersion: "17.0",
        processingState: b.processingState ?? "VALID",
        usesNonExemptEncryption: false,
      },
      relationships: {
        preReleaseVersion:
          b.marketingVersion === undefined
            ? { links: { self: `${API}/v1/builds/${b.id}/relationships/preReleaseVersion` } }
            : {
                links: { self: `${API}/v1/builds/${b.id}/relationships/preReleaseVersion` },
                data: { type: "preReleaseVersions", id: `pre-${b.marketingVersion}` },
              },
      },
      links: { self: `${API}/v1/builds/${b.id}` },
    })),
    included,
    links: { self: `${API}/v1/builds?filter[app]=${APP_ID}` },
    meta: { paging: { total: builds.length, limit: 1 } },
  };
}

export interface VersionFx {
  id: string;
  versionString: string;
  /** Sets `appVersionState` (current API). */
  state?: string;
  /** Sets the deprecated `appStoreState` (older responses). Pass `legacyOnly` to omit appVersionState. */
  legacyState?: string;
  legacyOnly?: boolean;
  releaseType?: string | null;
}

export function versionsDoc(versions: VersionFx[]) {
  return {
    data: versions.map((v) => ({
      type: "appStoreVersions",
      id: v.id,
      attributes: {
        platform: "IOS",
        versionString: v.versionString,
        ...(v.legacyOnly ? {} : { appVersionState: v.state }),
        appStoreState: v.legacyState ?? v.state,
        copyright: "2026 Dynex bv",
        reviewType: "APP_STORE",
        releaseType: v.releaseType === undefined ? "AFTER_APPROVAL" : v.releaseType,
        earliestReleaseDate: null,
        downloadable: false,
        createdDate: "2026-10-04T08:00:00-07:00",
      },
      relationships: {
        app: { links: { self: `${API}/v1/appStoreVersions/${v.id}/relationships/app` } },
        build: { links: { self: `${API}/v1/appStoreVersions/${v.id}/relationships/build` } },
      },
      links: { self: `${API}/v1/appStoreVersions/${v.id}` },
    })),
    links: { self: `${API}/v1/apps/${APP_ID}/appStoreVersions` },
    meta: { paging: { total: versions.length, limit: 10 } },
  };
}

export function singleVersionDoc(v: VersionFx) {
  return { data: versionsDoc([v]).data[0], links: { self: `${API}/v1/appStoreVersions/${v.id}` } };
}

export interface LocalizationFx {
  id: string;
  locale: string;
  whatsNew?: string | null;
}

export function localizationsDoc(locs: LocalizationFx[]) {
  return {
    data: locs.map((l) => ({
      type: "appStoreVersionLocalizations",
      id: l.id,
      attributes: { locale: l.locale, whatsNew: l.whatsNew === undefined ? null : l.whatsNew },
      links: { self: `${API}/v1/appStoreVersionLocalizations/${l.id}` },
    })),
    links: { self: `${API}/v1/appStoreVersions/x/appStoreVersionLocalizations` },
    meta: { paging: { total: locs.length, limit: 200 } },
  };
}

/** GET /v1/appStoreVersions/{id}/relationships/build */
export function buildLinkageDoc(buildId: string | null) {
  return { data: buildId === null ? null : { type: "builds", id: buildId }, links: { self: `${API}/x`, related: `${API}/y` } };
}

/** GET /v1/appStoreVersions/{id}/relationships/appStoreVersionPhasedRelease */
export function phasedLinkageDoc(id: string | null) {
  return { data: id === null ? null : { type: "appStoreVersionPhasedReleases", id }, links: { self: `${API}/x`, related: `${API}/y` } };
}

export interface ReviewDetailFx {
  id?: string;
  demoAccountRequired?: boolean | null;
  demoAccountName?: string | null;
}

/** GET /v1/appStoreVersions/{id}/appStoreReviewDetail (only the requested fields come back). */
export function reviewDetailDoc(d: ReviewDetailFx | null) {
  if (d === null) return { data: null, links: { self: `${API}/v1/appStoreVersions/x/appStoreReviewDetail` } };
  return {
    data: {
      type: "appStoreReviewDetails",
      id: d.id ?? "rd-1",
      attributes: { demoAccountRequired: d.demoAccountRequired ?? null, demoAccountName: d.demoAccountName ?? null },
      links: { self: `${API}/v1/appStoreReviewDetails/${d.id ?? "rd-1"}` },
    },
    links: { self: `${API}/v1/appStoreVersions/x/appStoreReviewDetail` },
  };
}

export interface SubmissionFx {
  id: string;
  state: string;
}

/** GET /v1/reviewSubmissions?filter[app]=… */
export function submissionsDoc(subs: SubmissionFx[]) {
  return {
    data: subs.map((s) => ({
      type: "reviewSubmissions",
      id: s.id,
      attributes: { platform: "IOS", state: s.state, submittedDate: null },
      relationships: {
        app: { links: { self: `${API}/v1/reviewSubmissions/${s.id}/relationships/app` } },
        items: { links: { self: `${API}/v1/reviewSubmissions/${s.id}/relationships/items` } },
      },
      links: { self: `${API}/v1/reviewSubmissions/${s.id}` },
    })),
    links: { self: `${API}/v1/reviewSubmissions` },
    meta: { paging: { total: subs.length, limit: 10 } },
  };
}

export interface ItemFx {
  id: string;
  /** Version this item submits; omit for a non-version item (event, in-app purchase, …). */
  versionId?: string;
}

/** GET /v1/reviewSubmissions/{id}/items?include=appStoreVersion */
export function submissionItemsDoc(items: ItemFx[]) {
  return {
    data: items.map((i) => ({
      type: "reviewSubmissionItems",
      id: i.id,
      attributes: { state: "READY_FOR_REVIEW" },
      relationships: {
        appStoreVersion:
          i.versionId === undefined
            ? { links: { self: `${API}/x` } }
            : { links: { self: `${API}/x` }, data: { type: "appStoreVersions", id: i.versionId } },
        appEvent: { links: { self: `${API}/y` } },
      },
      links: { self: `${API}/v1/reviewSubmissionItems/${i.id}` },
    })),
    included: items.flatMap((i) =>
      i.versionId === undefined ? [] : [{ type: "appStoreVersions", id: i.versionId, attributes: { versionString: "x" } }],
    ),
    links: { self: `${API}/v1/reviewSubmissions/x/items` },
    meta: { paging: { total: items.length, limit: 200 } },
  };
}

export const errorDoc = (status: number, code: string, detail: string) => ({
  errors: [{ id: "err-1", status: String(status), code, title: code, detail }],
});
