import type { JsonApiDoc, JsonApiResource } from "./http";
import type { AppVersion, Build, Localization, OpenSubmission, ReviewDetail } from "./model";

/** Pure translation of App Store Connect JSON:API documents into the domain model. */

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const bool = (v: unknown): boolean | null => (typeof v === "boolean" ? v : null);

type Doc<T> = Pick<JsonApiDoc<T>, "data" | "included">;

function relatedId(r: JsonApiResource, rel: string): string | null {
  const data = r.relationships?.[rel]?.data as { id?: unknown } | null | undefined;
  return typeof data?.id === "string" ? data.id : null;
}

/** First resource of `GET /v1/builds?filter[processingState]=VALID&sort=-uploadedDate&include=preReleaseVersion`. */
export function parseNewestBuild(doc: Doc<JsonApiResource[]>): Build | null {
  const b = doc.data[0];
  if (!b) return null;
  // The filter should already guarantee this; re-check so a stray PROCESSING/FAILED build is never released.
  if (b.attributes?.processingState !== "VALID") return null;
  const preId = relatedId(b, "preReleaseVersion");
  const pre = (doc.included ?? []).find((i) => i.type === "preReleaseVersions" && i.id === preId);
  return {
    id: b.id,
    buildNumber: str(b.attributes?.version) ?? "?",
    marketingVersion: str(pre?.attributes?.version),
    uploadedDate: str(b.attributes?.uploadedDate),
  };
}

function toVersion(r: JsonApiResource): AppVersion {
  return {
    id: r.id,
    versionString: str(r.attributes?.versionString) ?? "",
    // appStoreState is deprecated in favour of appVersionState (App Store Connect API 3.7); accept either.
    state: str(r.attributes?.appVersionState) ?? str(r.attributes?.appStoreState),
    releaseType: str(r.attributes?.releaseType),
  };
}

export function parseVersions(doc: Doc<JsonApiResource[]>): AppVersion[] {
  return doc.data.map(toVersion);
}

export function parseLocalizations(doc: Doc<JsonApiResource[]>): Localization[] {
  return doc.data.map((r) => ({
    id: r.id,
    locale: str(r.attributes?.locale) ?? "?",
    whatsNew: str(r.attributes?.whatsNew),
  }));
}

/** Id from a to-one linkage document (`GET …/relationships/<name>`); null when empty or absent. */
export function parseLinkageId(doc: { data: { id?: string } | null } | null): string | null {
  return doc?.data?.id ?? null;
}

export function parseReviewDetail(doc: { data: JsonApiResource | null } | null): ReviewDetail | null {
  const r = doc?.data;
  if (!r) return null;
  return {
    demoAccountRequired: bool(r.attributes?.demoAccountRequired),
    demoAccountName: str(r.attributes?.demoAccountName),
  };
}

export function parseSubmissionIds(doc: Doc<JsonApiResource[]>): string[] {
  return doc.data.map((r) => r.id);
}

/** `GET /v1/reviewSubmissions/{id}/items?include=appStoreVersion`. */
export function parseOpenSubmission(id: string, doc: Doc<JsonApiResource[]>): OpenSubmission {
  const versionIds: string[] = [];
  let otherItemCount = 0;
  for (const item of doc.data) {
    const versionId = relatedId(item, "appStoreVersion");
    if (versionId) versionIds.push(versionId);
    else otherItemCount++;
  }
  return { id, versionIds, otherItemCount };
}
