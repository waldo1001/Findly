import { appendFileSync } from "node:fs";
import { oneLine, splitLines } from "./text";

export interface SummaryIo {
  append: (path: string, data: string) => void;
  print: (text: string) => void;
}

const defaultIo: SummaryIo = {
  append: (path, data) => appendFileSync(path, data, "utf8"),
  print: (text) => console.log(text),
};

/**
 * Writer for the Markdown job summary: appends to `$GITHUB_STEP_SUMMARY` when set, otherwise prints
 * (local runs). Failing to write the summary must never fail the release, so it falls back to printing.
 */
export function makeSummaryWriter(path: string | undefined, io: SummaryIo = defaultIo): (markdown: string) => void {
  return (markdown) => {
    if (path !== undefined) {
      try {
        io.append(path, `${markdown}\n`);
        return;
      } catch {
        // fall through to printing
      }
    }
    // Printing to the job log: every line goes through oneLine so none can start a workflow command.
    io.print(splitLines(markdown).map(oneLine).join("\n"));
  };
}
