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
    [`POST /edits/${EDIT_ID}:commit`]: jsonResponse(appEdit),
    [`DELETE /edits/${EDIT_ID}`]: emptyResponse(204),
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
