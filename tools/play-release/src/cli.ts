// CLI entry: `node dist/cli.js`, configured entirely through the environment (never argv, so no secret
// can show up in a process listing). Two modes, picked by PLAY_RELEASE_MODE:
//
//   release (default, also when unset) — promote the Internal testing release to Production and Alpha:
//     PLAY_SERVICE_ACCOUNT_JSON  the service-account key JSON (required; never logged)
//     RELEASE_NOTES              plain text, 1-500 characters, used for every language (required)
//     DRY_RUN                    exactly "true" or "false" (required — anything else fails closed)
//
//   upload-internal — upload an AAB to the Internal testing track (docs/store-readiness.md §5, A59):
//     PLAY_SERVICE_ACCOUNT_JSON  as above
//     AAB_PATH                   the bundle to upload (required; a missing, unreadable or empty file is refused)
//     DRY_RUN                    must NOT be set: this mode has no dry run, and a flag that silently did
//                                nothing would be a lie
//
//   GITHUB_STEP_SUMMARY          set by GitHub Actions; a Markdown summary is appended to it
//
// Exit code 0: released, dry-run validated, nothing to release, uploaded, or upload deferred. Exit code 1:
// anything else. All input is validated before the first network call.

import { appendFileSync, readFileSync } from "node:fs";
import { fetchAccessToken, parseServiceAccount } from "./auth";
import type { FetchFn, MaskFn } from "./auth";
import { PACKAGE_NAME } from "./config";
import { PlayClient } from "./play-client";
import { checkNotes } from "./plan";
import { release } from "./release";
import { renderInternalSummary, renderSummary } from "./summary";
import { DEFERRED_NOTICE, uploadInternal } from "./upload-internal";

export interface CliDeps {
  fetchFn: FetchFn;
  /** Current time in milliseconds. */
  now: () => number;
  log: (line: string) => void;
  /** Registers a derived credential (signed assertion, access token) for redaction. Defaults to `::add-mask::` on GitHub Actions (`GITHUB_ACTIONS=true`) and to a no-op elsewhere. */
  mask: MaskFn;
}

type Mode = "release" | "upload-internal";

/** Everything a mode needs from the outside, resolved once by `run`. */
interface Io {
  fetchFn: FetchFn;
  now: () => number;
  log: (line: string) => void;
  mask: MaskFn;
  writeSummary: (markdown: string) => void;
}

type Env = Record<string, string | undefined>;

function parseDryRun(value: string | undefined): boolean {
  if (value === "true") return true;
  if (value === "false") return false;
  // Fail closed: guessing wrong in either direction is worse than refusing to run.
  throw new Error("DRY_RUN must be exactly 'true' or 'false'.");
}

function parseMode(value: string | undefined): Mode {
  // Unset means the original release flow, so existing callers (which never set it) are unchanged.
  if (value === undefined || value === "release") return "release";
  if (value === "upload-internal") return "upload-internal";
  // Fail closed: a typo must not fall back to a mode the caller did not ask for.
  throw new Error("PLAY_RELEASE_MODE must be exactly 'release' or 'upload-internal' (or unset, meaning 'release').");
}

/** The bundle, read whole. Only fixed messages: nothing about its contents ever reaches a log. */
function readBundle(path: string | undefined): Buffer {
  if (path === undefined || path.trim() === "") throw new Error("AAB_PATH is not set or empty.");
  let bytes: Buffer;
  try {
    bytes = readFileSync(path);
  } catch {
    throw new Error("AAB_PATH does not point to a readable file.");
  }
  if (bytes.length === 0) throw new Error("The file at AAB_PATH is empty.");
  return bytes;
}

/** Escape a message for a workflow command such as `::error::` (GitHub's documented data escaping). */
function escapeAnnotation(message: string): string {
  return message.replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
}

export async function run(env: Env, deps: Partial<CliDeps> = {}): Promise<number> {
  const fetchFn: FetchFn = deps.fetchFn ?? ((url, init) => fetch(url, init));
  const now = deps.now ?? Date.now;
  const sink = deps.log ?? ((line: string) => console.log(line));
  // One log call = one physical line. Text that reaches here can include Play's own error
  // messages; a newline in one must not be able to begin a `::workflow-command::` line.
  const log = (line: string): void => sink(line.replace(/[\r\n]+/g, " "));
  // `::add-mask::` makes the runner redact the value from every later log line. The command line is
  // consumed by the runner, so the value itself is not printed there. Anywhere else (a local `npm run
  // release`) nothing consumes it and the terminal would show the credential in clear text, so the
  // default hook only acts on GitHub Actions.
  const mask: MaskFn =
    deps.mask ??
    (env.GITHUB_ACTIONS === "true" ? (secret: string) => log(`::add-mask::${escapeAnnotation(secret)}`) : () => undefined);

  const summaryPath = env.GITHUB_STEP_SUMMARY === undefined || env.GITHUB_STEP_SUMMARY === "" ? undefined : env.GITHUB_STEP_SUMMARY;
  const writeSummary = (markdown: string): void => {
    if (summaryPath === undefined) return;
    try {
      appendFileSync(summaryPath, `${markdown}\n`);
    } catch {
      log("Warning: could not write the step summary.");
    }
  };

  const io: Io = { fetchFn, now, log, mask, writeSummary };

  let mode: Mode;
  try {
    mode = parseMode(env.PLAY_RELEASE_MODE);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error.";
    log(`::error::${escapeAnnotation(message)}`);
    writeSummary(renderSummary({ status: "failed", message, dryRun: undefined }));
    return 1;
  }

  return mode === "upload-internal" ? runUploadInternal(env, io) : runRelease(env, io);
}

async function runRelease(env: Env, io: Io): Promise<number> {
  const { fetchFn, now, log, mask, writeSummary } = io;

  let dryRun: boolean | undefined;
  try {
    dryRun = parseDryRun(env.DRY_RUN);
    const notes = checkNotes(env.RELEASE_NOTES);
    if (!notes.ok) throw new Error(notes.error.message);
    const serviceAccount = parseServiceAccount(env.PLAY_SERVICE_ACCOUNT_JSON);

    // The assertion and the token are masked inside fetchAccessToken (before the request and right
    // after the exchange), so nothing is narrated until both are registered.
    const token = await fetchAccessToken(fetchFn, serviceAccount, Math.floor(now() / 1000), mask);
    log(`${dryRun ? "Dry run" : "Real run"}: promoting the Internal testing release of ${PACKAGE_NAME} to Production and Closed testing – Alpha.`);
    // A dry-run client cannot commit at all — structural, on top of release()'s own flag check.
    const api = new PlayClient(fetchFn, token, PACKAGE_NAME, { dryRun });
    const outcome = await release({ api, notes: env.RELEASE_NOTES, dryRun, log });

    writeSummary(renderSummary({ status: "ok", outcome, dryRun }));
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error.";
    log(`::error::${escapeAnnotation(message)}`);
    writeSummary(renderSummary({ status: "failed", message, dryRun }));
    return 1;
  }
}

async function runUploadInternal(env: Env, io: Io): Promise<number> {
  const { fetchFn, now, log, mask, writeSummary } = io;

  try {
    // No dry run here (it runs only on main pushes). A DRY_RUN that was set would otherwise be
    // silently ignored while the run commits for real — refuse it instead.
    if (env.DRY_RUN !== undefined) {
      throw new Error("DRY_RUN must not be set in upload-internal mode: this mode has no dry run.");
    }
    const bundle = readBundle(env.AAB_PATH);
    const serviceAccount = parseServiceAccount(env.PLAY_SERVICE_ACCOUNT_JSON);

    // Masking is done inside fetchAccessToken, exactly as in release mode.
    const token = await fetchAccessToken(fetchFn, serviceAccount, Math.floor(now() / 1000), mask);
    log(`Uploading a bundle of ${PACKAGE_NAME} to the Internal testing track.`);
    const api = new PlayClient(fetchFn, token, PACKAGE_NAME);
    const outcome = await uploadInternal({ api, bundle, log });

    if (outcome.kind === "deferred") log(`::notice::${escapeAnnotation(DEFERRED_NOTICE)}`);
    writeSummary(renderInternalSummary({ status: "ok", outcome }));
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error.";
    log(`::error::${escapeAnnotation(message)}`);
    writeSummary(renderInternalSummary({ status: "failed", message }));
    return 1;
  }
}

if (require.main === module) {
  run(process.env).then((code) => {
    process.exitCode = code;
  });
}
