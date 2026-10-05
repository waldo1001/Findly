// CLI entry: `node dist/cli.js`, configured entirely through the environment (never argv, so no secret
// can show up in a process listing):
//
//   PLAY_SERVICE_ACCOUNT_JSON  the service-account key JSON (required; never logged)
//   RELEASE_NOTES              plain text, 1-500 characters, used for every language (required)
//   DRY_RUN                    exactly "true" or "false" (required — anything else fails closed)
//   GITHUB_STEP_SUMMARY        set by GitHub Actions; a Markdown summary is appended to it
//
// Exit code 0: released, dry-run validated, or nothing to release. Exit code 1: anything else.
// All input is validated before the first network call.

import { appendFileSync } from "node:fs";
import { fetchAccessToken, parseServiceAccount } from "./auth";
import type { FetchFn, MaskFn } from "./auth";
import { PACKAGE_NAME } from "./config";
import { PlayClient } from "./play-client";
import { checkNotes } from "./plan";
import { release } from "./release";
import { renderSummary } from "./summary";

export interface CliDeps {
  fetchFn: FetchFn;
  /** Current time in milliseconds. */
  now: () => number;
  log: (line: string) => void;
  /** Registers a derived credential (signed assertion, access token) for redaction. Defaults to `::add-mask::`. */
  mask: MaskFn;
}

function parseDryRun(value: string | undefined): boolean {
  if (value === "true") return true;
  if (value === "false") return false;
  // Fail closed: guessing wrong in either direction is worse than refusing to run.
  throw new Error("DRY_RUN must be exactly 'true' or 'false'.");
}

/** Escape a message for a `::error::` workflow command (GitHub's documented data escaping). */
function escapeAnnotation(message: string): string {
  return message.replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
}

export async function run(env: Record<string, string | undefined>, deps: Partial<CliDeps> = {}): Promise<number> {
  const fetchFn: FetchFn = deps.fetchFn ?? ((url, init) => fetch(url, init));
  const now = deps.now ?? Date.now;
  const sink = deps.log ?? ((line: string) => console.log(line));
  // One log call = one physical line. Text that reaches here can include Play's own error
  // messages; a newline in one must not be able to begin a `::workflow-command::` line.
  const log = (line: string): void => sink(line.replace(/[\r\n]+/g, " "));
  // `::add-mask::` makes the runner redact the value from every later log line. The command line is
  // consumed by the runner, so the value itself is not printed.
  const mask: MaskFn = deps.mask ?? ((secret: string) => log(`::add-mask::${escapeAnnotation(secret)}`));

  const summaryPath = env.GITHUB_STEP_SUMMARY === undefined || env.GITHUB_STEP_SUMMARY === "" ? undefined : env.GITHUB_STEP_SUMMARY;
  const writeSummary = (markdown: string): void => {
    if (summaryPath === undefined) return;
    try {
      appendFileSync(summaryPath, `${markdown}\n`);
    } catch {
      log("Warning: could not write the step summary.");
    }
  };

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

if (require.main === module) {
  run(process.env).then((code) => {
    process.exitCode = code;
  });
}
