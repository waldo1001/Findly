// The orchestration around one internal-track upload (docs/store-readiness.md §5, "Android
// internal-track upload (A59)"): upload the bundle, set the Internal testing track to it, commit —
// all in one Play edit. This replaces r0adkll/upload-google-play, which cannot pass
// `changesInReviewBehavior`: Play's default for it (CANCEL_IN_REVIEW_AND_SUBMIT) would cancel a
// production review in progress on an ordinary push. Safety properties kept here:
//   - the commit says ERROR_IF_IN_REVIEW, always; a refusal because changes are already in review is
//     a clean "deferred" (nothing cancelled, nothing published), never a failure;
//   - the one other refusal that has a way forward — Play insisting the edit be committed with
//     changesNotSentForReview — gets exactly one retry, with ERROR_IF_IN_REVIEW still on;
//   - "deferred" and every failure delete the edit — only a successful commit keeps it;
//   - a failure surfaces the *original* error, whatever the cleanup does.

import { requiresChangesNotSentForReview } from "./play-client";
import type { CommitResult, PlayApi } from "./play-client";

const INTERNAL_TRACK = "internal";

/** The `::notice::` text of a deferred upload (the CLI escapes it like every annotation). */
export const DEFERRED_NOTICE =
  "production review in progress — internal upload deferred; the next main build after the review uploads";

/**
 * `committed`: the bundle is on the Internal testing track. `notSentForReview` says it went through
 * the retry — committed with `changesNotSentForReview=true`.
 * `deferred`: Play refused because changes are already in review; the edit (and the uploaded bundle
 * with it) was discarded and nothing changed.
 */
export type InternalOutcome =
  | { kind: "committed"; versionCode: number; notSentForReview: boolean }
  | { kind: "deferred"; versionCode: number };

export interface UploadInternalOptions {
  api: PlayApi;
  /** The AAB, already read — never logged. */
  bundle: Uint8Array;
  log?: (line: string) => void;
}

export async function uploadInternal(options: UploadInternalOptions): Promise<InternalOutcome> {
  const { api, bundle } = options;
  const log = options.log ?? (() => undefined);

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
    log(`Uploading the bundle (${bundle.byteLength} bytes) into a new Play edit.`);
    const versionCode = await api.uploadBundle(editId, bundle);
    log(`Play accepted the bundle as version code ${versionCode}.`);

    log(`Setting the Internal testing track to version code ${versionCode} (completed).`);
    await api.updateTrack(editId, {
      track: INTERNAL_TRACK,
      releases: [{ versionCodes: [String(versionCode)], status: "completed" }],
    });

    const deferred = async (): Promise<InternalOutcome> => {
      log(
        "Play refused the commit: changes are already in review (production). Not cancelled; " +
          "the upload is deferred and the edit discarded.",
      );
      await discard();
      finished = true;
      return { kind: "deferred", versionCode };
    };

    let first: CommitResult;
    try {
      first = await api.commit(editId);
    } catch (error) {
      if (!requiresChangesNotSentForReview(error)) throw error;
      log(
        `Play refused to submit the change for review automatically (${error.message}). ` +
          "Retrying the commit once with changesNotSentForReview=true and ERROR_IF_IN_REVIEW.",
      );
      const retried = await api.commit(editId, { changesNotSentForReview: true });
      if (retried === "changes-in-review") return await deferred();
      finished = true;
      log("Committed (not sent for review): the bundle is on the Internal testing track.");
      return { kind: "committed", versionCode, notSentForReview: true };
    }

    if (first === "changes-in-review") return await deferred();
    finished = true;
    log("Committed: the bundle is on the Internal testing track.");
    return { kind: "committed", versionCode, notSentForReview: false };
  } finally {
    // Reached on success too; `finished` says whether the edit was already settled (committed
    // or discarded above). Only a failure in between leaves it open.
    if (!finished) await discard();
  }
}
