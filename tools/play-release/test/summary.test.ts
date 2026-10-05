import { describe, expect, it } from "vitest";
import { renderSummary } from "../src/summary";
import type { Outcome } from "../src/release";

// Markdown for $GITHUB_STEP_SUMMARY (docs/store-readiness.md §5, "Output"): platform, version,
// what changed, the state afterwards, a console link — and nothing secret.

const released = (kind: "dry-run" | "committed"): Outcome => ({
  kind,
  versionCodes: ["234"],
  languages: ["en-GB", "nl-BE"],
  notesLength: 27,
  before: { production: ["230"], alpha: ["231"] },
});

const nothing: Outcome = { kind: "nothing", versionCodes: ["234"], production: ["234"], alpha: ["231"] };

describe("renderSummary()", () => {
  it("committed: platform, version codes, both tracks, sent for review, console link", () => {
    const md = renderSummary({ status: "ok", outcome: released("committed"), dryRun: false });
    expect(md).toContain("com.findly.android");
    expect(md).toMatch(/Committed/);
    expect(md).toMatch(/sent for review/i);
    expect(md).toContain("234");
    expect(md).toMatch(/Production/);
    expect(md).toMatch(/Alpha/);
    expect(md).toContain("230");
    expect(md).toContain("231");
    expect(md).toContain("en-GB, nl-BE");
    expect(md).toContain("27 characters");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/dry run/i);
  });

  it("dry run: says plainly that nothing changed and what would have been set", () => {
    const md = renderSummary({ status: "ok", outcome: released("dry-run"), dryRun: true });
    expect(md).toMatch(/Dry run/);
    expect(md).toMatch(/nothing changed/i);
    expect(md).toContain("234");
    expect(md).toMatch(/would/i);
    expect(md).not.toMatch(/sent for review/i);
    expect(md).toContain("https://play.google.com/console");
  });

  it("nothing to release: names the version already live on production", () => {
    const md = renderSummary({ status: "ok", outcome: nothing, dryRun: false });
    expect(md).toMatch(/Nothing to release/);
    expect(md).toContain("234");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/sent for review/i);
  });

  it("failure: states it failed, quotes the reason, links the console, claims no change", () => {
    const md = renderSummary({ status: "failed", message: "Play API POST /edits failed (HTTP 403): no permission", dryRun: false });
    expect(md).toMatch(/Failed/);
    expect(md).toContain("HTTP 403");
    expect(md).toContain("no permission");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/Committed/);
  });

  it("failure: a message containing backticks cannot break out of the code block", () => {
    const md = renderSummary({ status: "failed", message: "bad ``` fence\n# injected heading", dryRun: undefined });
    const fences = md.split("\n").filter((line) => line.trim().startsWith("```"));
    expect(fences).toHaveLength(2);
  });

  it("failure before the mode is known still renders", () => {
    expect(() => renderSummary({ status: "failed", message: "DRY_RUN must be 'true' or 'false'.", dryRun: undefined })).not.toThrow();
  });

  it("states the mode of the run", () => {
    expect(renderSummary({ status: "ok", outcome: nothing, dryRun: true })).toMatch(/dry run/i);
    expect(renderSummary({ status: "ok", outcome: nothing, dryRun: false })).toMatch(/real run|committed/i);
  });
});
