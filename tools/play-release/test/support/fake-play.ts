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
/** Where `edits.bundles.upload` lives: the media-upload twin of BASE (Discovery document: `mediaUpload.protocols.simple.path`). */
export const UPLOAD_BASE = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/com.findly.android";
export const EDIT_ID = "EDIT123";
export const TOKEN = "ya29.fake-test-token";

/** The commit route. Play's default would cancel changes already in review, so the tool must say otherwise. */
export const COMMIT = `POST /edits/${EDIT_ID}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW`;

/** The read-only (outside any edit) `applications.tracks.releases.list` route. */
export const PRODUCTION_RELEASES = "GET /tracks/production/releases";

// --- upload-internal (A59) -------------------------------------------------------------------
// In recorded paths an upload URL appears as "/upload/edits/…" (UPLOAD_BASE is replaced by
// "/upload"); the exact URL is asserted separately wherever it matters.

/** `edits.bundles.upload`, simple media upload. */
export const UPLOAD = `POST /upload/edits/${EDIT_ID}/bundles?uploadType=media`;
export const INTERNAL_PUT = `PUT /edits/${EDIT_ID}/tracks/internal`;
/** The retry commit: the refusal said Play wants changesNotSentForReview; ERROR_IF_IN_REVIEW stays. */
export const COMMIT_UNSENT = `POST /edits/${EDIT_ID}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW&changesNotSentForReview=true`;
export const DELETE_EDIT = `DELETE /edits/${EDIT_ID}`;
/** The version code Play reports for the uploaded bundle in the default routes. */
export const UPLOADED_VERSION_CODE = 235;

export type Reply = () => Response;

export interface Recorded {
  method: string;
  url: string;
  /** The URL with the per-application prefix removed, e.g. "/edits/EDIT123/tracks/internal". */
  path: string;
  headers: Record<string, string>;
  /** The JSON body, when the request carried one. */
  body: unknown;
  /** The raw bytes, when the request carried binary content (a bundle upload). */
  bytes: Uint8Array | undefined;
  /** The abort signal the request carried. */
  signal: AbortSignal | null | undefined;
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

/** `Bundle`, the response of `edits.bundles.upload` (Discovery schema: sha1, sha256, versionCode int32). */
export function bundleResponse(...args: [] | [unknown]): Reply {
  // An explicit `undefined` means "a response without a versionCode" (the key is dropped by JSON), not "the default".
  const versionCode = args.length === 0 ? UPLOADED_VERSION_CODE : args[0];
  return jsonResponse({ versionCode, sha1: "da39a3ee5e6b4b0d3255bfef95601890afd80709", sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" });
}

/** The refusal Play sent on 2026-08-16 when an edit could not be auto-submitted (the post-rejection state). */
export function changesCannotBeSentAutomatically(
  message = "Changes cannot be sent for review automatically.",
): Reply {
  return playError(400, message, "FAILED_PRECONDITION");
}

/** The refusal Play sent on 2026-10-05 for the *old* flag: the opposite instruction. */
export function changesAreSentAutomatically(): Reply {
  return playError(
    400,
    "Changes are sent for review automatically. The query parameter changesNotSentForReview must not be set",
    "FAILED_PRECONDITION",
  );
}

/** The extra routes an upload-internal run uses, on top of `defaultRoutes()` (insert, commit, delete). */
export function internalUploadRoutes(): Record<string, Reply> {
  return {
    [UPLOAD]: bundleResponse(),
    [INTERNAL_PUT]: jsonResponse({ track: "internal" }),
  };
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
    const path = url.startsWith(BASE)
      ? url.slice(BASE.length)
      : url.startsWith(UPLOAD_BASE)
        ? `/upload${url.slice(UPLOAD_BASE.length)}`
        : url;
    const headers: Record<string, string> = {};
    for (const [key, value] of Object.entries((init?.headers ?? {}) as Record<string, string>)) {
      headers[key.toLowerCase()] = value;
    }
    const body = typeof init?.body === "string" ? (JSON.parse(init.body) as unknown) : undefined;
    const bytes = init?.body instanceof Uint8Array ? init.body : undefined;
    calls.push({ method, url, path, headers, body, bytes, signal: init?.signal });

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
