import { describe, expect, it } from "vitest";
import { renderSummary } from "../src/summary";
import type { Outcome } from "../src/release";

// Markdown for $GITHUB_STEP_SUMMARY (docs/store-readiness.md §5, "Output"): platform, release name
// and version codes, what changed, the store state afterwards (the production release's
// releaseLifecycleState), a console link — and nothing secret.

const inReview = {
  name: "1.2.0 (234)",
  versionCodes: ["234"],
  status: "completed",
  lifecycleState: "RELEASE_LIFECYCLE_STATE_IN_REVIEW",
};
const published = { ...inReview, lifecycleState: "RELEASE_LIFECYCLE_STATE_PUBLISHED" };

const base = {
  versionCodes: ["234"],
  name: "1.2.0 (234)",
  before: { production: ["230"], alpha: ["231"] },
  productionNow: [inReview],
};

const released = (kind: "dry-run" | "committed", overrides: Partial<Outcome> = {}): Outcome =>
  ({
    ...base,
    kind,
    languages: ["en-GB", "nl-BE"],
    notesLength: 27,
    ...(kind === "dry-run" ? { productionNow: [{ ...published, name: "1.1.0 (230)", versionCodes: ["230"] }] } : {}),
    ...overrides,
  }) as Outcome;

const nothing = (overrides: Partial<Outcome> = {}): Outcome =>
  ({
    ...base,
    kind: "nothing",
    before: { production: ["234"], alpha: ["231"] },
    productionNow: [published],
    ...overrides,
  }) as Outcome;

const stopped: Outcome = { ...base, kind: "stopped", reason: "changes-in-review" };

describe("renderSummary()", () => {
  it("committed: platform, release name AND version codes, both tracks, sent for review, state, console link", () => {
    const md = renderSummary({ status: "ok", outcome: released("committed"), dryRun: false });
    expect(md).toContain("com.findly.android");
    expect(md).toMatch(/Committed/);
    expect(md).toMatch(/sent for review/i);
    expect(md).toContain("1.2.0 (234)");
    expect(md).toContain("234");
    expect(md).toMatch(/Production/);
    expect(md).toMatch(/Alpha/);
    expect(md).toContain("230");
    expect(md).toContain("231");
    expect(md).toContain("en-GB, nl-BE");
    expect(md).toContain("27 characters");
    expect(md).toContain("IN_REVIEW");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/dry run/i);
  });

  it("strips the RELEASE_LIFECYCLE_STATE_ prefix, but never invents a state", () => {
    const md = renderSummary({ status: "ok", outcome: released("committed"), dryRun: false });
    expect(md).not.toContain("RELEASE_LIFECYCLE_STATE_");
    const unknown = renderSummary({
      status: "ok",
      outcome: released("committed", { productionNow: [{ ...inReview, lifecycleState: undefined }] }),
      dryRun: false,
    });
    expect(unknown).toMatch(/state not reported/i);
  });

  it("works when Play gave the release no name", () => {
    const md = renderSummary({ status: "ok", outcome: released("committed", { name: undefined }), dryRun: false });
    expect(md).toContain("234");
    expect(md).not.toContain("undefined");
  });

  it("dry run: says plainly that nothing changed, what would have been set, and the CURRENT production state", () => {
    const md = renderSummary({ status: "ok", outcome: released("dry-run"), dryRun: true });
    expect(md).toMatch(/Dry run/);
    expect(md).toMatch(/nothing changed/i);
    expect(md).toContain("1.2.0 (234)");
    expect(md).toMatch(/would/i);
    expect(md).toContain("PUBLISHED");
    expect(md).not.toMatch(/sent for review/i);
    expect(md).toContain("https://play.google.com/console");
  });

  it("nothing to release: names the release already on production and its real state", () => {
    const md = renderSummary({ status: "ok", outcome: nothing(), dryRun: false });
    expect(md).toMatch(/Nothing to release/);
    expect(md).toContain("1.2.0 (234)");
    expect(md).toContain("PUBLISHED");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/sent for review/i);
  });

  it("nothing to release: must not claim 'completed' when the state says IN_REVIEW", () => {
    const md = renderSummary({ status: "ok", outcome: nothing({ productionNow: [inReview] }), dryRun: false });
    expect(md).toContain("IN_REVIEW");
    expect(md).not.toMatch(/completed/i);
  });

  it("nothing to release: with the state unreadable it says so and still claims nothing about 'completed'", () => {
    const md = renderSummary({ status: "ok", outcome: nothing({ productionNow: undefined }), dryRun: false });
    expect(md).toMatch(/unavailable/i);
    expect(md).not.toMatch(/completed/i);
  });

  it("stopped: production has changes in review — nothing was changed, no 'Committed'", () => {
    const md = renderSummary({ status: "ok", outcome: stopped, dryRun: false });
    expect(md).toMatch(/Stopped/);
    expect(md).toMatch(/changes in review/i);
    expect(md).toMatch(/nothing (was )?changed/i);
    expect(md).toContain("1.2.0 (234)");
    expect(md).toContain("https://play.google.com/console");
    expect(md).not.toMatch(/Committed/);
  });

  it("lists every production release Play reports, with its state", () => {
    const md = renderSummary({
      status: "ok",
      outcome: released("committed", {
        productionNow: [inReview, { ...published, name: "1.1.0 (230)", versionCodes: ["230"] }],
      }),
      dryRun: false,
    });
    expect(md).toContain("1.1.0 (230)");
    expect(md).toContain("PUBLISHED");
    expect(md).toContain("IN_REVIEW");
  });

  it("production state unreadable: says so, does not fail", () => {
    const md = renderSummary({ status: "ok", outcome: released("committed", { productionNow: undefined }), dryRun: false });
    expect(md).toMatch(/unavailable/i);
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
    const md = renderSummary({ status: "failed", message: "bad\n```\n# injected heading", dryRun: undefined });
    const fences = md.split("\n").filter((line) => line.trim().startsWith("```"));
    expect(fences).toHaveLength(2);
  });

  it("a release name with markdown or table characters cannot break the table", () => {
    const md = renderSummary({
      status: "ok",
      outcome: released("committed", { name: "evil | name\n# heading" }),
      dryRun: false,
    });
    expect(md).not.toMatch(/^# heading/m);
    const rows = md.split("\n").filter((l) => l.startsWith("|"));
    for (const row of rows) expect(row.match(/(?<!\\)\|/g)!.length).toBe(rows[0]!.match(/(?<!\\)\|/g)!.length);
  });

  it("failure before the mode is known still renders", () => {
    expect(() => renderSummary({ status: "failed", message: "DRY_RUN must be 'true' or 'false'.", dryRun: undefined })).not.toThrow();
  });

  it("states the mode of the run", () => {
    expect(renderSummary({ status: "ok", outcome: nothing(), dryRun: true })).toMatch(/dry run/i);
    expect(renderSummary({ status: "ok", outcome: nothing(), dryRun: false })).toMatch(/real run|committed/i);
  });
});
