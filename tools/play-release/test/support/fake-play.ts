import type { FetchFn } from "../../src/auth";
import alphaOlder from "../fixtures/alpha-older.json";
import internalCompleted from "../fixtures/internal-completed.json";
import listings from "../fixtures/listings.json";
import trackEmpty from "../fixtures/track-empty.json";

// A scripted stand-in for the Play Developer API, driven through the `fetch` seam. Routes are
// keyed "METHOD /path-after-the-application" and hold *factories* (a Response body can be read
// only once). An unrouted request throws, so a call the code was not supposed to make fails the
// test loudly instead of silently succeeding.

export const BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.findly.android";
export const EDIT_ID = "EDIT123";
export const TOKEN = "ya29.fake-test-token";

/** The commit route. Play's default would cancel changes already in review, so the tool must say otherwise. */
export const COMMIT = `POST /edits/${EDIT_ID}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW`;

/** The read-only (outside any edit) `applications.tracks.releases.list` route. */
export const PRODUCTION_RELEASES = "GET /tracks/production/releases";

export type Reply = () => Response;

export interface Recorded {
  method: string;
  url: string;
  /** The URL with the per-application prefix removed, e.g. "/edits/EDIT123/tracks/internal". */
  path: string;
  headers: Record<string, string>;
  body: unknown;
}

export function jsonResponse(body: unknown, status = 200): Reply {
  return () =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export function emptyResponse(status = 204): Reply {
  return () => new Response(null, { status });
}

export function playError(status: number, message: string, apiStatus = "FAILED_PRECONDITION"): Reply {
  return jsonResponse({ error: { code: status, message, status: apiStatus } }, status);
}

/**
 * One entry of `applications.tracks.releases.list`, in the shape of Google's Discovery document
 * (schema `ReleaseSummary`): `releaseName`, `track`, `activeArtifacts[]` (each `versionCode`, an
 * int32 JSON *number*) and `releaseLifecycleState`. Nothing else — in particular no `versionCodes`,
 * `status` or `lastUpdateTime`, which belong to the edits API's `TrackRelease`.
 */
export function releaseSummary(
  releaseName: string,
  versionCodes: number[],
  state: "DRAFT" | "NOT_SENT_FOR_REVIEW" | "IN_REVIEW" | "APPROVED_NOT_PUBLISHED" | "NOT_APPROVED" | "PUBLISHED",
) {
  return {
    releaseName,
    track: "production",
    activeArtifacts: versionCodes.map((versionCode) => ({ versionCode })),
    releaseLifecycleState: `RELEASE_LIFECYCLE_STATE_${state}`,
  };
}

/** `ListReleaseSummariesResponse`: `{ releases: [ReleaseSummary…] }`. */
export function releaseSummaries(...releases: ReturnType<typeof releaseSummary>[]): Reply {
  return jsonResponse({ releases });
}

/** The refusal Play sends for `ERROR_IF_IN_REVIEW` when changes are already in review. */
export function changesAlreadyInReview(): Reply {
  return jsonResponse(
    {
      error: {
        code: 400,
        message: "Changes are already in review.",
        status: "FAILED_PRECONDITION",
        details: [
          {
            "@type": "type.googleapis.com/google.rpc.ErrorInfo",
            reason: "CHANGES_ALREADY_IN_REVIEW",
            domain: "googleapis.com",
            metadata: { editId: EDIT_ID, method: "google.play.developer.v3.EditsService.CommitEdit", service: "androidpublisher.googleapis.com" },
          },
        ],
      },
    },
    400,
  );
}

const appEdit = { id: EDIT_ID, expiryTimeSeconds: "1760003600" };

export function defaultRoutes(): Record<string, Reply> {
  return {
    "POST /edits": jsonResponse(appEdit),
    [`GET /edits/${EDIT_ID}/tracks/internal`]: jsonResponse(internalCompleted),
    [`GET /edits/${EDIT_ID}/tracks/production`]: jsonResponse(trackEmpty),
    [`GET /edits/${EDIT_ID}/tracks/alpha`]: jsonResponse(alphaOlder),
    [`GET /edits/${EDIT_ID}/listings`]: jsonResponse(listings),
    [`PUT /edits/${EDIT_ID}/tracks/production`]: jsonResponse({ track: "production" }),
    [`PUT /edits/${EDIT_ID}/tracks/alpha`]: jsonResponse({ track: "alpha" }),
    [`POST /edits/${EDIT_ID}:validate`]: jsonResponse(appEdit),
    [COMMIT]: jsonResponse(appEdit),
    [`DELETE /edits/${EDIT_ID}`]: emptyResponse(204),
    // Default: what production looks like once the new release has been submitted.
    [PRODUCTION_RELEASES]: releaseSummaries(releaseSummary("1.2.0 (234)", [234], "IN_REVIEW")),
  };
}

export function createFakePlay(overrides: Record<string, Reply> = {}) {
  const routes = { ...defaultRoutes(), ...overrides };
  const calls: Recorded[] = [];

  const fetchFn: FetchFn = async (url, init) => {
    const method = init?.method ?? "GET";
    const path = url.startsWith(BASE) ? url.slice(BASE.length) : url;
    const headers: Record<string, string> = {};
    for (const [key, value] of Object.entries((init?.headers ?? {}) as Record<string, string>)) {
      headers[key.toLowerCase()] = value;
    }
    const body = typeof init?.body === "string" ? (JSON.parse(init.body) as unknown) : undefined;
    calls.push({ method, url, path, headers, body });

    const reply = routes[`${method} ${path}`];
    if (!reply) throw new Error(`fake Play: unexpected request ${method} ${path}`);
    return reply();
  };

  return {
    fetchFn,
    calls,
    /** "METHOD /path" for every request, in order. */
    sequence: () => calls.map((c) => `${c.method} ${c.path}`),
  };
}
