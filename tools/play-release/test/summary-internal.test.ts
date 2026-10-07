import { describe, expect, it } from "vitest";
import { renderInternalSummary } from "../src/summary";
import type { InternalOutcome } from "../src/upload-internal";

// The short $GITHUB_STEP_SUMMARY of an internal-track upload (docs/store-readiness.md §5, "Android
// internal-track upload (A59)"): the version code that was uploaded and the outcome — nothing else,
// and nothing secret.

const committed: InternalOutcome = { kind: "committed", versionCode: 235, notSentForReview: false };
const committedUnsent: InternalOutcome = { kind: "committed", versionCode: 235, notSentForReview: true };
const deferred: InternalOutcome = { kind: "deferred", versionCode: 235 };

describe("renderInternalSummary()", () => {
  it("committed: app, internal track, version code, result, console link", () => {
    const md = renderInternalSummary({ status: "ok", outcome: committed });
    expect(md).toContain("com.findly.android");
    expect(md).toMatch(/Internal testing/);
    expect(md).toContain("235");
    expect(md).toMatch(/Committed/);
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/deferred/i);
    expect(md).not.toMatch(/failed/i);
  });

  it("committed through the retry: says it was committed without being sent for review", () => {
    const md = renderInternalSummary({ status: "ok", outcome: committedUnsent });
    expect(md).toMatch(/Committed/);
    expect(md).toMatch(/not sent for review/i);
    expect(md).toContain("235");
  });

  it("the plain committed summary does not claim 'not sent for review'", () => {
    expect(renderInternalSummary({ status: "ok", outcome: committed })).not.toMatch(/not sent for review/i);
  });

  it("deferred: says so, says why, says the next main build uploads, and that nothing was published or cancelled", () => {
    const md = renderInternalSummary({ status: "ok", outcome: deferred });
    expect(md).toMatch(/Deferred/);
    expect(md).toMatch(/production review in progress/i);
    expect(md).toMatch(/next main build/i);
    expect(md).toMatch(/not (been )?(published|uploaded)|nothing was (published|changed)/i);
    expect(md).toMatch(/not cancelled|never cancel/i);
    expect(md).toContain("235");
    expect(md).not.toMatch(/Committed/);
  });

  it("failed: the reason in a fenced block, the console link, no success wording", () => {
    const md = renderInternalSummary({ status: "failed", message: "Play API POST /edits/1/bundles failed (HTTP 400): Version code 235 has already been used." });
    expect(md).toMatch(/Failed/);
    expect(md).toContain("```");
    expect(md).toContain("Version code 235 has already been used.");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/Committed|Deferred/);
  });

  it("a failure message cannot break out of its fenced block", () => {
    const md = renderInternalSummary({ status: "failed", message: "oops ``` # injected heading" });
    expect(md.match(/```/g)).toHaveLength(2);
  });

  it("is short: a handful of lines, not a report", () => {
    for (const outcome of [committed, committedUnsent, deferred]) {
      expect(renderInternalSummary({ status: "ok", outcome }).split("\n").length).toBeLessThanOrEqual(16);
    }
  });
});
