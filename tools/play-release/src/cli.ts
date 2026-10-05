// RED stub — signatures only, behaviour arrives in the green commit.

import type { FetchFn } from "./auth";

export interface CliDeps {
  fetchFn: FetchFn;
  /** Current time in milliseconds. */
  now: () => number;
  log: (line: string) => void;
}

export async function run(_env: Record<string, string | undefined>, _deps?: Partial<CliDeps>): Promise<number> {
  throw new Error("not implemented");
}
