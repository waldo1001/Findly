import { describe, expect, it } from "vitest";
import type { ReleaseResult } from "../src/release";
import { CONSOLE_LINK, renderSummary } from "../src/summary";

const base: ReleaseResult = {
  outcome: "submitted",
  dryRun: false,
  message: "Submitted 1.2.0 (build 240) for App Review.",
  version: "1.2.0",
  buildNumber: "240",
  stateBefore: "PREPARE_FOR_SUBMISSION",
  stateAfter: "WAITING_FOR_REVIEW",
  steps: [
    { description: "Set What's New (en-GB, 47 characters)", status: "done" },
    { description: "Attach build 240 to the version", status: "done" },
  ],
  notes: "Faster map refresh.",
};

describe("renderSummary", () => {
  it("shows platform, version, build, what changed, the resulting state and the console link", () => {
    const md = renderSummary(base);
    expect(md).toContain("iOS");
    expect(md).toContain("1.2.0");
    expect(md).toContain("240");
    expect(md).toContain("Set What's New (en-GB, 47 characters)");
    expect(md).toContain("WAITING_FOR_REVIEW");
    expect(md).toContain("https://appstoreconnect.apple.com/apps/6797994768/distribution");
    expect(CONSOLE_LINK).toBe("https://appstoreconnect.apple.com/apps/6797994768/distribution");
  });

  it("marks a dry run unmistakably and labels steps as planned", () => {
    const md = renderSummary({
      ...base,
      outcome: "dry-run",
      dryRun: true,
      stateAfter: null,
      steps: [{ description: "Submit the new review submission to App Review", status: "planned" }],
    });
    expect(md).toMatch(/dry run/i);
    expect(md).toMatch(/nothing was changed/i);
    expect(md).toMatch(/planned/i);
  });

  it("explains a stop, with the state, and lists no steps", () => {
    const md = renderSummary({
      ...base,
      outcome: "stopped",
      message: "Version 1.2.0 (build 240) is already WAITING_FOR_REVIEW. Nothing to submit; no changes made.",
      stateBefore: "WAITING_FOR_REVIEW",
      stateAfter: null,
      steps: [],
    });
    expect(md).toContain("WAITING_FOR_REVIEW");
    expect(md).toMatch(/stopped|nothing to submit/i);
    expect(md).not.toMatch(/Steps/);
  });

  it("reports a failure with the message and per-step outcomes", () => {
    const md = renderSummary({
      ...base,
      outcome: "failed",
      message: "PATCH /v1/appStoreVersions/v1/relationships/build failed: HTTP 409: Missing export compliance.",
      stateAfter: null,
      steps: [
        { description: "Set What's New (en-GB, 47 characters)", status: "done" },
        { description: "Attach build 240 to the version", status: "failed" },
        { description: "Submit the new review submission to App Review", status: "skipped" },
      ],
    });
    expect(md).toMatch(/failed/i);
    expect(md).toContain("Missing export compliance.");
    expect(md).toMatch(/skipped/i);
  });

  it("works when nothing was resolved yet (e.g. no build)", () => {
    const md = renderSummary({ ...base, outcome: "failed", version: null, buildNumber: null, stateBefore: null, stateAfter: null, steps: [], message: "No processed build found." });
    expect(md).toContain("No processed build found.");
    expect(md).toContain(CONSOLE_LINK);
  });

  it("keeps HTML in untrusted text from rendering", () => {
    const md = renderSummary({ ...base, outcome: "failed", message: "boom <img src=x onerror=alert(1)> & more" });
    expect(md).not.toContain("<img");
    expect(md).toContain("&lt;img");
  });

  it("shows the release notes in a code fence that cannot be closed from inside", () => {
    const md = renderSummary({ ...base, notes: "line one\n```\n# injected heading\n```" });
    const fence = md.match(/^(`{3,})$/m)?.[1] ?? "";
    expect(fence.length).toBeGreaterThanOrEqual(4);
    expect(md).toContain("line one");
  });

  it("contains no secret-shaped material", () => {
    expect(renderSummary(base)).not.toMatch(/BEGIN [A-Z ]*PRIVATE KEY|Bearer |eyJ[A-Za-z0-9_-]{10,}\./);
  });
});
