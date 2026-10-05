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

  it("the stdout fallback goes through per-line oneLine: no line can start a workflow command", () => {
    const printed: string[] = [];
    const evil = "## ok\n::add-mask::oops\n\u2028::error::spoof\nfine";
    makeSummaryWriter(undefined, { append: () => {}, print: (s) => printed.push(s) })(evil);
    const lines = printed.join("\n").split("\n");
    expect(lines.some((l) => l.startsWith("::"))).toBe(false);
    expect(lines).toContain("## ok");
    expect(lines).toContain("fine");
  });

  it("the fallback after a failed file write is sanitised the same way", () => {
    const printed: string[] = [];
    makeSummaryWriter("/nope/summary.md", {
      append: () => {
        throw new Error("ENOENT");
      },
      print: (s) => printed.push(s),
    })("::stop-commands::x");
    expect(printed.join("\n").startsWith("::")).toBe(false);
  });
});
