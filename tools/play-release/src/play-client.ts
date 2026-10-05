// Thin HTTP client for the Google Play Developer API v3 (androidpublisher): one method per call the
// release flow needs, no decisions. Built on an injected `fetch` so the whole thing runs against a
// stub in unit tests. Error messages carry Play's own `error.message` and the HTTP status, never
// the request (which holds the bearer token) and never an unparsed response body.

import type { FetchFn } from "./auth";
import type { Track, TrackBody } from "./plan";

const API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

const REQUEST_TIMEOUT_MS = 60_000;

export class PlayApiError extends Error {
  readonly status: number;
  /** Machine-readable error reasons from the response (`error.details[].reason`, `error.errors[].reason`). */
  readonly reasons: string[];

  constructor(message: string, status: number, reasons: string[] = []) {
    super(message);
    this.name = "PlayApiError";
    this.status = status;
    this.reasons = reasons;
  }
}

/** The Play Developer API calls the release flow needs, one method each. */
export interface PlayApi {
  /** `edits.insert` — returns the new edit's id. */
  insertEdit(): Promise<string>;
  /** `edits.tracks.get` — `undefined` when Play answers 404 (no such track). */
  getTrack(editId: string, track: string): Promise<Track | undefined>;
  /** `edits.listings.list` — the language of every store listing. */
  listListingLanguages(editId: string): Promise<string[]>;
  /** `edits.tracks.update` — replaces the track's releases with `body.releases`. */
  updateTrack(editId: string, body: TrackBody): Promise<void>;
  /** `edits.validate`. */
  validate(editId: string): Promise<void>;
  /** `edits.commit` — without `changesNotSentForReview`, so the change is sent for review. */
  commit(editId: string): Promise<CommitResult>;
  /** `edits.delete` — discards the edit. */
  deleteEdit(editId: string): Promise<void>;
  /** `applications.tracks.releases.list` — read-only, outside any edit. */
  listReleases(track: string): Promise<ReleaseSummary[]>;
}

/** `changes-in-review`: Play refused (ERROR_IF_IN_REVIEW) because changes are already in review. */
export type CommitResult = "committed" | "changes-in-review";

/**
 * One entry of `applications.tracks.releases.list`, exactly as Google's Discovery document
 * (androidpublisher v3, schema `ReleaseSummary`) defines it: `releaseName`, `track`,
 * `activeArtifacts[]` (each `ArtifactSummary { versionCode: int32 }`) and `releaseLifecycleState`.
 * Nothing else exists on this schema — `versionCodes`, `status` and `lastUpdateTime` belong to the
 * edits API's `TrackRelease`, not here.
 */
export interface ReleaseSummary {
  releaseName?: string;
  track?: string;
  activeArtifacts?: { versionCode: number }[];
  /** e.g. RELEASE_LIFECYCLE_STATE_IN_REVIEW. */
  releaseLifecycleState?: string;
}

export interface ClientOptions {
  /** A dry-run client refuses to commit, structurally — on top of the caller's own flag check. */
  dryRun?: boolean;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseJson(text: string): unknown {
  if (text === "") return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

function playMessage(payload: unknown): string | undefined {
  if (!isRecord(payload) || !isRecord(payload.error)) return undefined;
  const message = payload.error.message;
  return typeof message === "string" && message !== "" ? message : undefined;
}

/** Google's error body carries the reason twice over: `details[]` (ErrorInfo) and the legacy `errors[]`. */
function playReasons(payload: unknown): string[] {
  if (!isRecord(payload) || !isRecord(payload.error)) return [];
  const entries = [payload.error.details, payload.error.errors].flatMap((list) => (Array.isArray(list) ? list : []));
  return entries.flatMap((entry: unknown) => (isRecord(entry) && typeof entry.reason === "string" ? [entry.reason] : []));
}

/** The path as shown in messages: without the query string. */
const labelOf = (path: string): string => path.split("?")[0] ?? path;

/** CHANGES_ALREADY_IN_REVIEW, changesAlreadyInReview, … all compare equal. */
const normalizeReason = (reason: string): string => reason.replace(/[^a-z0-9]/gi, "").toLowerCase();

const IN_REVIEW_REASON = normalizeReason("CHANGES_ALREADY_IN_REVIEW");

const optionalString = (value: unknown): string | undefined => (typeof value === "string" ? value : undefined);

export class PlayClient implements PlayApi {
  private readonly base: string;
  private readonly dryRun: boolean;

  constructor(
    private readonly fetchFn: FetchFn,
    private readonly accessToken: string,
    packageName: string,
    options: ClientOptions = {},
  ) {
    this.base = `${API_ROOT}/${encodeURIComponent(packageName)}`;
    this.dryRun = options.dryRun === true;
  }

  private async request(
    method: string,
    path: string,
    body?: unknown,
  ): Promise<{ status: number; payload: unknown }> {
    const headers: Record<string, string> = {
      authorization: `Bearer ${this.accessToken}`,
      accept: "application/json",
    };
    if (body !== undefined) headers["content-type"] = "application/json";

    let response: Response;
    try {
      response = await this.fetchFn(`${this.base}${path}`, {
        method,
        headers,
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      // Only the error's *name* is kept (e.g. TimeoutError): its message may quote the request.
      const name = error instanceof Error ? error.name : "unknown";
      throw new PlayApiError(`Play API ${method} ${labelOf(path)} failed: network error (${name}).`, 0);
    }

    const payload = parseJson(await response.text());
    // A 404 is returned to the caller: for `getTrack` it means "no such track", everywhere else
    // `call()` turns it into an error.
    if (!response.ok && response.status !== 404) {
      throw this.failure(method, path, response.status, payload);
    }
    return { status: response.status, payload };
  }

  private failure(method: string, path: string, status: number, payload: unknown): PlayApiError {
    const message = playMessage(payload);
    return new PlayApiError(
      `Play API ${method} ${labelOf(path)} failed (HTTP ${status})${message ? `: ${message}` : "."}`,
      status,
      playReasons(payload),
    );
  }

  /** Like `request`, but a 404 is an error too. */
  private async call(method: string, path: string, body?: unknown): Promise<unknown> {
    const { status, payload } = await this.request(method, path, body);
    if (status === 404) throw this.failure(method, path, status, payload);
    return payload;
  }

  async insertEdit(): Promise<string> {
    const payload = await this.call("POST", "/edits");
    const id = isRecord(payload) ? payload.id : undefined;
    if (typeof id !== "string" || id === "") {
      throw new PlayApiError("Play API POST /edits returned no edit id.", 200);
    }
    return id;
  }

  async getTrack(editId: string, track: string): Promise<Track | undefined> {
    const path = `/edits/${encodeURIComponent(editId)}/tracks/${encodeURIComponent(track)}`;
    const { status, payload } = await this.request("GET", path);
    if (status === 404) return undefined;
    if (!isRecord(payload)) {
      throw new PlayApiError(`Play API GET ${path} returned no track data.`, status);
    }
    return payload as Track;
  }

  async listListingLanguages(editId: string): Promise<string[]> {
    const payload = await this.call("GET", `/edits/${encodeURIComponent(editId)}/listings`);
    const listings = isRecord(payload) && Array.isArray(payload.listings) ? payload.listings : [];
    return listings.flatMap((listing: unknown) =>
      isRecord(listing) && typeof listing.language === "string" ? [listing.language] : [],
    );
  }

  async updateTrack(editId: string, body: TrackBody): Promise<void> {
    await this.call("PUT", `/edits/${encodeURIComponent(editId)}/tracks/${encodeURIComponent(body.track)}`, body);
  }

  async validate(editId: string): Promise<void> {
    await this.call("POST", `/edits/${encodeURIComponent(editId)}:validate`);
  }

  async commit(editId: string): Promise<CommitResult> {
    if (this.dryRun) {
      // Structural guard behind the caller's own dry-run flag: no request is even built.
      throw new Error("Refusing to commit: this client was created for a dry run.");
    }
    // Play's default (CANCEL_IN_REVIEW_AND_SUBMIT) would silently cancel changes already in review
    // and resubmit; ERROR_IF_IN_REVIEW makes Play refuse instead. changesNotSentForReview is
    // deliberately never set: an edit must go to review, not sit unsent.
    const path = `/edits/${encodeURIComponent(editId)}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW`;
    try {
      await this.call("POST", path);
      return "committed";
    } catch (error) {
      const refused =
        error instanceof PlayApiError &&
        error.status === 400 &&
        error.reasons.some((reason) => normalizeReason(reason) === IN_REVIEW_REASON);
      if (refused) return "changes-in-review";
      throw error;
    }
  }

  async deleteEdit(editId: string): Promise<void> {
    await this.call("DELETE", `/edits/${encodeURIComponent(editId)}`);
  }

  async listReleases(track: string): Promise<ReleaseSummary[]> {
    const payload = await this.call("GET", `/tracks/${encodeURIComponent(track)}/releases`);
    const releases = isRecord(payload) && Array.isArray(payload.releases) ? payload.releases : [];
    return releases.flatMap((entry: unknown): ReleaseSummary[] => {
      if (!isRecord(entry)) return [];
      const summary: ReleaseSummary = {};
      const releaseName = optionalString(entry.releaseName);
      const trackName = optionalString(entry.track);
      const releaseLifecycleState = optionalString(entry.releaseLifecycleState);
      if (releaseName !== undefined) summary.releaseName = releaseName;
      if (trackName !== undefined) summary.track = trackName;
      if (Array.isArray(entry.activeArtifacts)) {
        // ArtifactSummary.versionCode is an int32, i.e. a JSON *number*; anything else is not a version code.
        summary.activeArtifacts = entry.activeArtifacts.flatMap((artifact: unknown) =>
          isRecord(artifact) && typeof artifact.versionCode === "number" && Number.isInteger(artifact.versionCode)
            ? [{ versionCode: artifact.versionCode }]
            : [],
        );
      }
      if (releaseLifecycleState !== undefined) summary.releaseLifecycleState = releaseLifecycleState;
      return [summary];
    });
  }
}
