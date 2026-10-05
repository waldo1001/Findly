import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { makeSummaryWriter } from "../src/summaryWriter";

describe("makeSummaryWriter ($GITHUB_STEP_SUMMARY)", () => {
  it("appends to the summary file when a path is set, keeping earlier content", () => {
    const dir = mkdtempSync(join(tmpdir(), "findly-summary-"));
    try {
      const file = join(dir, "summary.md");
      writeFileSync(file, "earlier step\n");
      makeSummaryWriter(file)("## iOS release");
      expect(readFileSync(file, "utf8")).toBe("earlier step\n## iOS release\n");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("prints to the console when there is no summary path (local runs)", () => {
    const printed: string[] = [];
    makeSummaryWriter(undefined, { append: () => { throw new Error("must not append"); }, print: (s) => printed.push(s) })("## hello");
    expect(printed).toEqual(["## hello"]);
  });

  it("falls back to printing when the file cannot be written; a summary problem must not fail the release", () => {
    const printed: string[] = [];
    const write = makeSummaryWriter("/nonexistent-dir/summary.md", {
      append: () => {
        throw new Error("ENOENT");
      },
      print: (s) => printed.push(s),
    });
    expect(() => write("## hello")).not.toThrow();
    expect(printed).toEqual(["## hello"]);
  });
});
