// RED stub — signatures only, behaviour arrives in the green commit.

import type { PlayApi } from "./play-client";
import type { PlanErrorCode } from "./plan";

export class ReleaseError extends Error {
  readonly code: PlanErrorCode;
  constructor(code: PlanErrorCode, message: string) {
    super(message);
    this.name = "ReleaseError";
    this.code = code;
  }
}

export interface NothingOutcome {
  kind: "nothing";
  versionCodes: string[];
  production: string[];
  alpha: string[];
}

export interface ReleasedOutcome {
  kind: "dry-run" | "committed";
  versionCodes: string[];
  languages: string[];
  notesLength: number;
  before: { production: string[]; alpha: string[] };
}

export type Outcome = NothingOutcome | ReleasedOutcome;

export interface ReleaseOptions {
  api: PlayApi;
  notes: string | undefined;
  dryRun: boolean;
  log?: (line: string) => void;
}

export async function release(_options: ReleaseOptions): Promise<Outcome> {
  throw new Error("not implemented");
}
