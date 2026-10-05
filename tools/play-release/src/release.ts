// The orchestration around one Play edit (docs/store-readiness.md §5, Android). The decision of what
// to release lives in plan.ts; this file only sequences the calls and guarantees the safety
// properties:
//   - bad release notes fail before a single Play call is made;
//   - a dry run validates the edit, then deletes it — it never commits;
//   - a change already in review is never cancelled: the commit says ERROR_IF_IN_REVIEW and a
//     refusal for that reason is a clean "stopped", not a failure;
//   - "nothing to release", "stopped" and every failure delete the edit — only a successful commit
//     keeps it;
//   - a failure surfaces the *original* error, whatever the cleanup does;
//   - the production state shown afterwards is read-only and best effort: it can never fail a run.

import { PlayApiError } from "./play-client";
import type { PlayApi, ReleaseSummary } from "./play-client";
import { checkNotes, plan } from "./plan";
import type { PlanErrorCode } from "./plan";

export class ReleaseError extends Error {
  readonly code: PlanErrorCode;

  constructor(code: PlanErrorCode, message: string) {
    super(message);
    this.name = "ReleaseError";
    this.code = code;
  }
}

/**
 * One production release as `applications.tracks.releases.list` reports it (schema `ReleaseSummary`):
 * its name, the version codes of its active artifacts, and its lifecycle state.
 */
export interface ProductionRelease {
  name?: string | undefined;
  /** From `activeArtifacts[].versionCode` (int32 numbers), as strings like everywhere else here. */
  versionCodes: string[];
  /** e.g. RELEASE_LIFECYCLE_STATE_IN_REVIEW. */
  lifecycleState?: string | undefined;
}

interface OutcomeBase {
  versionCodes: string[];
  /** Name of Internal's release, e.g. "1.2.0 (234)". */
  name?: string | undefined;
  /** Version codes of the current completed release on each track, before this run. */
  before: { production: string[]; alpha: string[] };
  /**
   * Production's releases as Play reports them once the run has settled (read-only, outside the
   * edit). `undefined` when that read failed — it is best effort and never fails the run.
   */
  productionNow: ProductionRelease[] | undefined;
}

export interface NothingOutcome extends OutcomeBase {
  kind: "nothing";
}

/** Play refused the commit because changes are already in review; nothing was changed. */
export interface StoppedOutcome extends OutcomeBase {
  kind: "stopped";
  reason: "changes-in-review";
}

export interface ReleasedOutcome extends OutcomeBase {
  /** `dry-run`: validated, then discarded. `committed`: sent for review. */
  kind: "dry-run" | "committed";
  languages: string[];
  notesLength: number;
}

export type Outcome = NothingOutcome | StoppedOutcome | ReleasedOutcome;

export interface ReleaseOptions {
  api: PlayApi;
  notes: string | undefined;
  dryRun: boolean;
  log?: (line: string) => void;
}

const list = (codes: string[]): string => (codes.length > 0 ? codes.join(", ") : "none");

const NEXT_STEP = "Next step: in Play Console open Publishing overview and choose Send changes for review.";
const NOT_COMMITTED = "Nothing was committed; re-run later.";
const NOT_CONFIRMED =
  "Play did not confirm the commit; re-run later (if it had gone through, the re-run reports nothing to release or stops on the change in review).";

/**
 * What the operator should do after a commit failed, by kind of failure:
 *  - a precondition-style refusal (400 FAILED_PRECONDITION / INVALID_ARGUMENT, 409, 412): the edit
 *    was valid but Play will not submit it as it stands — "Send changes for review" in the Console
 *    is the way forward;
 *  - a server error or a network failure (5xx, no response): the commit may or may not have been
 *    applied, so nothing is claimed either way — a re-run is safe and tells;
 *  - any other 4xx (401/403 auth, 404 edit gone, 429 quota, …): Play rejected the request itself, so
 *    nothing was committed, and the Play Console step would be the wrong advice.
 * The original Play message is always kept.
 */
function withNextStep(error: unknown): unknown {
  if (!(error instanceof PlayApiError)) return error;
  const suffix = [400, 409, 412].includes(error.status)
    ? NEXT_STEP
    : error.status === 0 || error.status >= 500
      ? NOT_CONFIRMED
      : NOT_COMMITTED;
  const end = /[.!?]$/.test(error.message) ? "" : ".";
  return new PlayApiError(`${error.message}${end} ${suffix}`, error.status, error.reasons);
}

/** Google's `ReleaseSummary` carries artifacts as `activeArtifacts[].versionCode` (int32 numbers). */
function toProductionRelease(summary: ReleaseSummary): ProductionRelease {
  return {
    name: summary.releaseName,
    versionCodes: (summary.activeArtifacts ?? []).map((artifact) => String(artifact.versionCode)),
    lifecycleState: summary.releaseLifecycleState,
  };
}

export async function release(options: ReleaseOptions): Promise<Outcome> {
  const { api, dryRun } = options;
  const log = options.log ?? (() => undefined);

  // Fail on bad notes before Play is touched at all.
  const notes = checkNotes(options.notes);
  if (!notes.ok) throw new ReleaseError(notes.error.code, notes.error.message);

  const editId = await api.insertEdit();

  // Best effort, never throws: an undeleted edit was never committed and expires by itself.
  const discard = async (): Promise<void> => {
    try {
      await api.deleteEdit(editId);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "unknown error";
      log(`Warning: could not delete the Play edit (${reason}). It was not committed and expires on its own.`);
    }
  };

  // Best effort, never throws: the state shown in the summary must not be able to fail a run whose
  // real work is already done (or deliberately not done).
  const readProduction = async (): Promise<ProductionRelease[] | undefined> => {
    try {
      return (await api.listReleases("production")).map(toProductionRelease);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "unknown error";
      log(`Warning: could not read the production release state (${reason}).`);
      return undefined;
    }
  };

  let finished = false;
  try {
    const internal = await api.getTrack(editId, "internal");
    const production = await api.getTrack(editId, "production");
    const alpha = await api.getTrack(editId, "alpha");
    const languages = await api.listListingLanguages(editId);

    const decision = plan({ internal, production, alpha }, languages, options.notes);

    if (decision.action === "error") {
      throw new ReleaseError(decision.code, decision.message);
    }

    if (decision.action === "nothing") {
      log(`Production already has version code(s) ${list(decision.versionCodes)} as a completed release — nothing to release.`);
      await discard();
      finished = true;
      return {
        kind: "nothing",
        versionCodes: decision.versionCodes,
        name: decision.name,
        before: { production: decision.production, alpha: decision.alpha },
        productionNow: await readProduction(),
      };
    }

    log(`Internal testing: completed release ${decision.name ? `${decision.name} ` : ""}with version code(s) ${list(decision.versionCodes)}.`);
    log(`Production now: ${list(decision.before.production)}. Alpha now: ${list(decision.before.alpha)}.`);
    log(
      `${dryRun ? "Would set" : "Setting"} production and alpha to version code(s) ${list(decision.versionCodes)} ` +
        `(completed, full rollout) with release notes in ${decision.languages.join(", ")}.`,
    );

    await api.updateTrack(editId, decision.bodies.production);
    await api.updateTrack(editId, decision.bodies.alpha);
    await api.validate(editId);
    log("Play validated the edit.");

    const facts = {
      versionCodes: decision.versionCodes,
      name: decision.name,
      before: decision.before,
    };

    if (dryRun) {
      await discard();
      finished = true;
      log("Dry run: the edit was discarded, nothing changed.");
      return {
        kind: "dry-run",
        ...facts,
        languages: decision.languages,
        notesLength: decision.notes.length,
        productionNow: await readProduction(),
      };
    }

    let result: Awaited<ReturnType<PlayApi["commit"]>>;
    try {
      result = await api.commit(editId);
    } catch (error) {
      throw withNextStep(error);
    }

    if (result === "changes-in-review") {
      log("Production has changes in review — stopped. Nothing was changed; the in-review change was not cancelled.");
      await discard();
      finished = true;
      return { kind: "stopped", reason: "changes-in-review", ...facts, productionNow: await readProduction() };
    }

    finished = true;
    log("Committed: the change is sent for review.");
    return {
      kind: "committed",
      ...facts,
      languages: decision.languages,
      notesLength: decision.notes.length,
      productionNow: await readProduction(),
    };
  } finally {
    // Reached on success too; `finished` says whether the edit was already settled (committed
    // or discarded above). Only a failure in between leaves it open.
    if (!finished) await discard();
  }
}
