// Markdown for $GITHUB_STEP_SUMMARY (docs/store-readiness.md §5, "Output"): platform, release name and
// version codes, what changed, the store state afterwards (the production release's
// releaseLifecycleState as Play reports it), a console link. Only facts about the release go in —
// never a secret, and the release-note text itself is not echoed (its length is enough; the run's
// inputs already show it). Everything that came from Play is escaped before it reaches Markdown.

import { CONSOLE_URL, PACKAGE_NAME } from "./config";
import type { Outcome, ProductionRelease } from "./release";

export type RunReport =
  | { status: "ok"; outcome: Outcome; dryRun: boolean }
  | { status: "failed"; message: string; dryRun: boolean | undefined };

const TRACKS = "Production, Closed testing – Alpha";

const list = (codes: string[]): string => (codes.length > 0 ? codes.join(", ") : "none");

const modeRow = (dryRun: boolean): string[] => [`| Mode | ${dryRun ? "Dry run" : "Real run"} |`];

/** A fenced block the message cannot break out of: backticks are the only way to close a fence. */
const fenced = (text: string): string => ["```", text.replace(/`/g, "'"), "```"].join("\n");

/** Text from Play, made safe for a table cell or a list item: one line, no Markdown or table syntax. */
const plain = (text: string): string =>
  text
    .replace(/\s*[\r\n]+\s*/g, " ")
    .replace(/[\\|`*_<>[\]]/g, (char) => `\\${char}`);

function table(rows: string[]): string[] {
  return ["| | |", "|---|---|", ...rows];
}

/** "1.2.0 (234) — version code(s) 234", or just the codes when Play gave the release no name. */
function releaseLabel(name: string | undefined, codes: string[]): string {
  return name ? `${plain(name)} — version code(s) ${list(codes)}` : `Version code(s) ${list(codes)}`;
}

/** RELEASE_LIFECYCLE_STATE_IN_REVIEW → IN_REVIEW. Never invents a state. */
function stateOf(release: ProductionRelease | undefined): string {
  const state = release?.lifecycleState;
  return state ? state.replace(/^RELEASE_LIFECYCLE_STATE_/, "") : "state not reported";
}

function sameCodes(a: string[], b: string[]): boolean {
  const left = [...a].sort();
  const right = [...b].sort();
  return left.length === right.length && left.every((code, i) => code === right[i]);
}

/** The "state afterwards" block: every production release Play reports, or why there is none. */
function productionBlock(releases: ProductionRelease[] | undefined): string[] {
  if (releases === undefined) {
    return ["**Production releases (Play):** state unavailable — it could not be read (the run itself is unaffected).", ""];
  }
  if (releases.length === 0) return ["**Production releases (Play):** none reported.", ""];
  return [
    "**Production releases (Play):**",
    "",
    ...releases.map((r) => `- ${r.name ? `${plain(r.name)} ` : ""}[${list(r.versionCodes)}] — ${stateOf(r)}`),
    "",
  ];
}

export function renderSummary(report: RunReport): string {
  const title = `## Google Play release — ${PACKAGE_NAME}`;
  const link = `[Open Play Console](${CONSOLE_URL})`;

  if (report.status === "failed") {
    const mode = report.dryRun === undefined ? [] : [`Mode: ${report.dryRun ? "dry run" : "real run"}.`, ""];
    return [title, "", "**Failed** — the run stopped with this reason:", "", fenced(report.message), "", ...mode, link, ""].join("\n");
  }

  const { outcome, dryRun } = report;
  const label = releaseLabel(outcome.name, outcome.versionCodes);

  if (outcome.kind === "nothing") {
    const live = outcome.productionNow?.find((r) => sameCodes(r.versionCodes, outcome.versionCodes));
    const state = outcome.productionNow === undefined ? "state unavailable" : stateOf(live);
    return [
      title,
      "",
      ...table([
        "| Result | **Nothing to release** |",
        ...modeRow(dryRun),
        `| Release | ${label} |`,
        `| Production | already has version code(s) ${list(outcome.versionCodes)} — ${state} |`,
        `| Closed testing – Alpha | ${list(outcome.before.alpha)} |`,
      ]),
      "",
      ...productionBlock(outcome.productionNow),
      link,
      "",
    ].join("\n");
  }

  if (outcome.kind === "stopped") {
    return [
      title,
      "",
      ...table([
        "| Result | **Stopped — production has changes in review** |",
        ...modeRow(dryRun),
        `| Release | ${label} (not submitted) |`,
      ]),
      "",
      "Play refused to submit this release because changes are already in review; the tool never cancels them. Nothing was changed. Wait for that review to finish (or cancel it yourself in Play Console → Publishing overview), then run again.",
      "",
      ...productionBlock(outcome.productionNow),
      link,
      "",
    ].join("\n");
  }

  const committed = outcome.kind === "committed";
  const codes = list(outcome.versionCodes);
  const after = committed ? codes : `${codes} (would be set)`;
  return [
    title,
    "",
    ...table([
      committed ? "| Result | **Committed — sent for review** |" : "| Result | **Dry run — nothing changed** |",
      ...modeRow(dryRun),
      `| Release | ${label} |`,
      `| Tracks | ${committed ? TRACKS : `${TRACKS} (would be updated)`} |`,
      `| Production | ${list(outcome.before.production)} → ${after} |`,
      `| Closed testing – Alpha | ${list(outcome.before.alpha)} → ${after} |`,
      `| Release notes | ${outcome.notesLength} characters, languages: ${outcome.languages.join(", ")} |`,
    ]),
    "",
    ...productionBlock(outcome.productionNow),
    link,
    "",
  ].join("\n");
}
