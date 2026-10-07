// Thin HTTP client for the Google Play Developer API v3 (androidpublisher): one method per call the
// release and the internal-upload flows need, no decisions. Built on an injected `fetch` so the whole
// thing runs against a stub in unit tests. Error messages carry Play's own `error.message` and the
// HTTP status, never the request (which holds the bearer token) and never an unparsed response body.

import type { FetchFn } from "./auth";
import type { ReleaseNote, Track } from "./plan";

const API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

/**
 * The media-upload twin of API_ROOT. Google's Discovery document (androidpublisher v3, method
 * `edits.bundles.upload`, `mediaUpload.protocols.simple.path`) puts a bundle upload at
 * `/upload/androidpublisher/v3/applications/{packageName}/edits/{editId}/bundles`, takes
 * `application/octet-stream` (max 50 GiB) and answers with a `Bundle { versionCode, sha1, sha256 }`.
 */
const UPLOAD_ROOT = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications";

const REQUEST_TIMEOUT_MS = 60_000;

/** Google asks for generous timeouts on this endpoint (the Discovery description recommends 2 minutes). */
const UPLOAD_TIMEOUT_MS = 300_000;

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

/**
 * Request body for `edits.tracks.update`. `TrackBody` (the release flow's: with release notes) fits;
 * so does a plain release without notes, which is what the internal track gets.
 */
export interface TrackUpdate {
  track: string;
  releases: { versionCodes: string[]; status: "completed"; releaseNotes?: ReleaseNote[] }[];
}

/** The Play Developer API calls the release and internal-upload flows need, one method each. */
export interface PlayApi {
  /** `edits.insert` — returns the new edit's id. */
  insertEdit(): Promise<string>;
  /** `edits.tracks.get` — `undefined` when Play answers 404 (no such track). */
  getTrack(editId: string, track: string): Promise<Track | undefined>;
  /** `edits.listings.list` — the language of every store listing. */
  listListingLanguages(editId: string): Promise<string[]>;
  /** `edits.tracks.update` — replaces the track's releases with `body.releases`. */
  updateTrack(editId: string, body: TrackUpdate): Promise<void>;
  /** `edits.bundles.upload` — returns the version code Play read from the uploaded bundle. */
  uploadBundle(editId: string, bundle: Uint8Array): Promise<number>;
  /** `edits.validate`. */
  validate(editId: string): Promise<void>;
  /**
   * `edits.commit` with `changesInReviewBehavior=ERROR_IF_IN_REVIEW` — always. Without
   * `changesNotSentForReview` unless the caller asks for it, so by default the change is sent for review.
   */
  commit(editId: string, options?: CommitOptions): Promise<CommitResult>;
  /** `edits.delete` — discards the edit. */
  deleteEdit(editId: string): Promise<void>;
  /** `applications.tracks.releases.list` — read-only, outside any edit. */
  listReleases(track: string): Promise<ReleaseSummary[]>;
}

/** `changes-in-review`: Play refused (ERROR_IF_IN_REVIEW) because changes are already in review. */
export type CommitResult = "committed" | "changes-in-review";

export interface CommitOptions {
  /**
   * Adds `changesNotSentForReview=true`: commit the edit without sending its changes for review.
   * Only the internal upload's one retry sets it, after Play refused to submit automatically.
   * `ERROR_IF_IN_REVIEW` stays on either way.
   */
  changesNotSentForReview?: boolean;
}

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
const NOT_SENT_REASON = normalizeReason("changesNotSentForReview");

/** The opposite refusal (2026-10-05, for the old flag): "…are sent for review automatically… must not be set". */
const MUST_NOT_SET = /must not be set|are sent for review automatically/i;
/** Observed 2026-08-16: "Changes cannot be sent for review automatically"; the parameter's name covers the rest. */
const NEEDS_NOT_SENT = /cannot be sent for review automatically|changesNotSentForReview/i;

/**
 * Is this commit refusal Play saying "this edit cannot be submitted for review automatically — commit
 * it with `changesNotSentForReview`" (the post-rejection state)? A 400 whose message says so (or whose
 * machine-readable reason names the parameter). Deliberately NOT the opposite refusal ("must not be
 * set"), which also names the parameter: retrying with the flag there would be exactly wrong.
 */
export function requiresChangesNotSentForReview(error: unknown): error is PlayApiError {
  if (!(error instanceof PlayApiError) || error.status !== 400) return false;
  if (MUST_NOT_SET.test(error.message)) return false;
  return NEEDS_NOT_SENT.test(error.message) || error.reasons.some((reason) => normalizeReason(reason).includes(NOT_SENT_REASON));
}

const optionalString = (value: unknown): string | undefined => (typeof value === "string" ? value : undefined);

export class PlayClient implements PlayApi {
  private readonly base: string;
  private readonly uploadBase: string;
  private readonly dryRun: boolean;

  constructor(
    private readonly fetchFn: FetchFn,
    private readonly accessToken: string,
    packageName: string,
    options: ClientOptions = {},
  ) {
    this.base = `${API_ROOT}/${encodeURIComponent(packageName)}`;
    this.uploadBase = `${UPLOAD_ROOT}/${encodeURIComponent(packageName)}`;
    this.dryRun = options.dryRun === true;
  }

  /** `media`: raw bytes for a media upload (the upload host path, `application/octet-stream`, a longer timeout). */
  private async request(
    method: string,
    path: string,
    body?: unknown,
    media?: Uint8Array,
  ): Promise<{ status: number; payload: unknown }> {
    const headers: Record<string, string> = {
      authorization: `Bearer ${this.accessToken}`,
      accept: "application/json",
    };
    if (body !== undefined) headers["content-type"] = "application/json";
    if (media !== undefined) headers["content-type"] = "application/octet-stream";

    let response: Response;
    try {
      response = await this.fetchFn(`${media !== undefined ? this.uploadBase : this.base}${path}`, {
        method,
        headers,
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
        ...(media !== undefined ? { body: media } : {}),
        signal: AbortSignal.timeout(media !== undefined ? UPLOAD_TIMEOUT_MS : REQUEST_TIMEOUT_MS),
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
  private async call(method: string, path: string, body?: unknown, media?: Uint8Array): Promise<unknown> {
    const { status, payload } = await this.request(method, path, body, media);
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

  async updateTrack(editId: string, body: TrackUpdate): Promise<void> {
    await this.call("PUT", `/edits/${encodeURIComponent(editId)}/tracks/${encodeURIComponent(body.track)}`, body);
  }

  async uploadBundle(editId: string, bundle: Uint8Array): Promise<number> {
    if (this.dryRun) {
      // Same structural guard as commit(): a dry-run client changes nothing in Play, not even a draft edit.
      throw new Error("Refusing to upload: this client was created for a dry run.");
    }
    const path = `/edits/${encodeURIComponent(editId)}/bundles?uploadType=media`;
    const payload = await this.call("POST", path, undefined, bundle);
    // Bundle.versionCode is an int32, i.e. a JSON *number*; anything else is not a version code.
    const versionCode = isRecord(payload) ? payload.versionCode : undefined;
    if (typeof versionCode !== "number" || !Number.isInteger(versionCode) || versionCode <= 0) {
      throw new PlayApiError(`Play API POST ${labelOf(path)} returned no version code for the uploaded bundle.`, 200);
    }
    return versionCode;
  }

  async validate(editId: string): Promise<void> {
    await this.call("POST", `/edits/${encodeURIComponent(editId)}:validate`);
  }

  async commit(editId: string, options: CommitOptions = {}): Promise<CommitResult> {
    if (this.dryRun) {
      // Structural guard behind the caller's own dry-run flag: no request is even built.
      throw new Error("Refusing to commit: this client was created for a dry run.");
    }
    // Play's default (CANCEL_IN_REVIEW_AND_SUBMIT) would silently cancel changes already in review
    // and resubmit; ERROR_IF_IN_REVIEW makes Play refuse instead — on every commit, with or without
    // the flag below. changesNotSentForReview is set only when the caller asks (the internal upload's
    // one retry, after Play said it cannot submit automatically); the release flow never does: its
    // edit must go to review, not sit unsent.
    const unsent = options.changesNotSentForReview === true ? "&changesNotSentForReview=true" : "";
    const path = `/edits/${encodeURIComponent(editId)}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW${unsent}`;
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
