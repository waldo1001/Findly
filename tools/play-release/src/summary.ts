// RED stub — signatures only, behaviour arrives in the green commit.

import type { Outcome } from "./release";

export type RunReport =
  | { status: "ok"; outcome: Outcome; dryRun: boolean }
  | { status: "failed"; message: string; dryRun: boolean | undefined };

export function renderSummary(_report: RunReport): string {
  throw new Error("not implemented");
}
