import { APP_APPLE_ID } from "./config";
import type { ReleaseResult, Step } from "./release";
import { escapeHtml } from "./text";

export const CONSOLE_LINK = `https://appstoreconnect.apple.com/apps/${APP_APPLE_ID}/distribution`;

const OUTCOME_LABEL: Record<ReleaseResult["outcome"], string> = {
  submitted: "Submitted for App Review",
  "dry-run": "Dry run: plan only",
  stopped: "Stopped: nothing to submit",
  failed: "Failed",
};

const STEP_LABEL: Record<Step["status"], string> = {
  planned: "planned",
  done: "done",
  failed: "FAILED",
  skipped: "skipped",
};

/** Untrusted text (Apple strings, version strings) -> safe inline Markdown. */
const text = (s: string): string => escapeHtml(s).replace(/\|/g, "\\|").replace(/\r?\n/g, " ");

function fenceFor(content: string): string {
  const longest = Math.max(0, ...(content.match(/`+/g) ?? []).map((m) => m.length));
  return "`".repeat(Math.max(3, longest + 1));
}

/** Markdown for $GITHUB_STEP_SUMMARY. Contains no credentials: only versions, states, step names. */
export function renderSummary(r: ReleaseResult): string {
  const lines: string[] = [];
  lines.push("## iOS release: Findly (`com.findly.ios`)", "");
  if (r.dryRun) {
    lines.push("> **DRY RUN.** Nothing was changed in App Store Connect; only read requests were sent.", "");
  }
  lines.push("| | |", "|---|---|");
  lines.push(`| Result | **${OUTCOME_LABEL[r.outcome]}** |`);
  lines.push(`| Version | ${r.version === null ? "n/a" : text(r.version)} |`);
  lines.push(`| Build | ${r.buildNumber === null ? "n/a" : text(r.buildNumber)} |`);
  if (r.stateBefore !== null) lines.push(`| State when checked | \`${text(r.stateBefore)}\` |`);
  if (r.stateAfter !== null) lines.push(`| State afterwards | \`${text(r.stateAfter)}\` |`);
  lines.push("", text(r.message), "");

  if (r.steps.length > 0) {
    lines.push(r.dryRun ? "### Changes it would make" : "### Changes", "");
    for (const s of r.steps) lines.push(`- **${STEP_LABEL[s.status]}**: ${text(s.description)}`);
    lines.push("");
  }

  const fence = fenceFor(r.notes);
  lines.push("### Release notes (What's New)", "", fence, r.notes, fence, "");
  lines.push(`[Open in App Store Connect](${CONSOLE_LINK})`, "");
  return lines.join("\n");
}
