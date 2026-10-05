// The orchestration around one Play edit (docs/store-readiness.md §5, Android). The decision of what
// to release lives in plan.ts; this file only sequences the calls and guarantees the safety
// properties:
//   - bad release notes fail before a single Play call is made;
//   - a dry run validates the edit, then deletes it — it never commits;
//   - "nothing to release" and every failure delete the edit — only a successful commit keeps it;
//   - a failure surfaces the *original* error, whatever the cleanup does.

import type { PlayApi } from "./play-client";
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

/** One production release as `applications.tracks.releases.list` reports it. */
export interface ProductionRelease {
  name?: string | undefined;
  versionCodes: string[];
  status?: string | undefined;
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
        productionNow: undefined,
      };
    }

    log(`Internal testing: completed release with version code(s) ${list(decision.versionCodes)}.`);
    log(`Production now: ${list(decision.before.production)}. Alpha now: ${list(decision.before.alpha)}.`);
    log(
      `${dryRun ? "Would set" : "Setting"} production and alpha to version code(s) ${list(decision.versionCodes)} ` +
        `(completed, full rollout) with release notes in ${decision.languages.join(", ")}.`,
    );

    await api.updateTrack(editId, decision.bodies.production);
    await api.updateTrack(editId, decision.bodies.alpha);
    await api.validate(editId);
    log("Play validated the edit.");

    const outcome = {
      versionCodes: decision.versionCodes,
      name: decision.name,
      languages: decision.languages,
      notesLength: decision.notes.length,
      before: decision.before,
      productionNow: undefined,
    };

    if (dryRun) {
      await discard();
      finished = true;
      log("Dry run: the edit was discarded, nothing changed.");
      return { kind: "dry-run", ...outcome };
    }

    await api.commit(editId);
    finished = true;
    log("Committed: the change is sent for review.");
    return { kind: "committed", ...outcome };
  } finally {
    // Reached on success too; `finished` says whether the edit was already settled (committed
    // or discarded above). Only a failure in between leaves it open.
    if (!finished) await discard();
  }
}
