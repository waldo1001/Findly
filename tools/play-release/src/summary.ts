// Markdown for $GITHUB_STEP_SUMMARY (docs/store-readiness.md §5, "Output"): platform, version, what
// changed, the state afterwards, a console link. Only facts about the release go in — never a
// secret, and the release-note text itself is not echoed (its length is enough; the run's inputs
// already show it).

import { CONSOLE_URL, PACKAGE_NAME } from "./config";
import type { Outcome } from "./release";

export type RunReport =
  | { status: "ok"; outcome: Outcome; dryRun: boolean }
  | { status: "failed"; message: string; dryRun: boolean | undefined };

const TRACKS = "Production, Closed testing – Alpha";

const list = (codes: string[]): string => (codes.length > 0 ? codes.join(", ") : "none");

const modeRow = (dryRun: boolean): string[] => [`| Mode | ${dryRun ? "Dry run" : "Real run"} |`];

/** A fenced block the message cannot break out of: backticks are the only way to close a fence. */
const fenced = (text: string): string => ["```", text.replace(/`/g, "'"), "```"].join("\n");

function table(rows: string[]): string[] {
  return ["| | |", "|---|---|", ...rows];
}

export function renderSummary(report: RunReport): string {
  const title = `## Google Play release — ${PACKAGE_NAME}`;
  const link = `[Open Play Console](${CONSOLE_URL})`;

  if (report.status === "failed") {
    const mode = report.dryRun === undefined ? [] : [`Mode: ${report.dryRun ? "dry run" : "real run"}.`, ""];
    return [title, "", "**Failed** — the run stopped with this reason:", "", fenced(report.message), "", ...mode, link, ""].join("\n");
  }

  const { outcome, dryRun } = report;

  if (outcome.kind === "nothing") {
    return [
      title,
      "",
      ...table([
        "| Result | **Nothing to release** |",
        ...modeRow(dryRun),
        `| Version code(s) | ${list(outcome.versionCodes)} |`,
        `| Production now | ${list(outcome.before.production)} — already a completed release |`,
        `| Closed testing – Alpha now | ${list(outcome.before.alpha)} |`,
      ]),
      "",
      link,
      "",
    ].join("\n");
  }

  if (outcome.kind === "stopped") {
    return [title, "", "**Stopped**", "", link, ""].join("\n");
  }

  const committed = outcome.kind === "committed";
  const codes = list(outcome.versionCodes);
  return [
    title,
    "",
    ...table([
      committed ? "| Result | **Committed — sent for review** |" : "| Result | **Dry run — nothing changed** |",
      ...modeRow(dryRun),
      `| Version code(s) | ${codes} |`,
      `| Tracks | ${TRACKS} |`,
      `| Production | ${list(outcome.before.production)} → ${committed ? codes : `${codes} (would be set)`} |`,
      `| Closed testing – Alpha | ${list(outcome.before.alpha)} → ${committed ? codes : `${codes} (would be set)`} |`,
      `| Release notes | ${outcome.notesLength} characters, languages: ${outcome.languages.join(", ")} |`,
    ]),
    "",
    link,
    "",
  ].join("\n");
}
