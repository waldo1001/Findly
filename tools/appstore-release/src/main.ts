import { ConfigError, loadConfig } from "./config";
import { AscClient } from "./http";
import { createTokenProvider } from "./jwt";
import { runRelease, type ReleaseResult } from "./release";
import { renderSummary } from "./summary";
import { oneLine } from "./text";

export interface CliDeps {
  env: Record<string, string | undefined>;
  /** Injectable for tests; defaults to the global fetch. */
  fetch?: typeof fetch;
  log: (line: string) => void;
  writeSummary: (markdown: string) => void;
}

function failure(message: string, notes: string): ReleaseResult {
  return { outcome: "failed", dryRun: false, message, version: null, buildNumber: null, stateBefore: null, stateAfter: null, steps: [], notes };
}

/** Returns the process exit code: 0 for submitted / dry run / stopped (nothing to do), 1 for any failure. */
export async function runCli(deps: CliDeps): Promise<number> {
  // Everything logged goes through oneLine(): store/operator text can never start a workflow command.
  const log = (line: string): void => deps.log(oneLine(line));

  let config;
  try {
    config = loadConfig(deps.env);
  } catch (e) {
    const message = e instanceof ConfigError ? e.message : "Unexpected configuration error.";
    log(`Configuration error: ${message}`);
    deps.writeSummary(renderSummary(failure(`Configuration error: ${message}`, "(not available)")));
    return 1;
  }

  const client = new AscClient({
    token: createTokenProvider({ keyId: config.keyId, issuerId: config.issuerId, privateKey: config.privateKey }),
    dryRun: config.dryRun,
    fetch: deps.fetch,
  });

  let result: ReleaseResult;
  try {
    result = await runRelease(client, { appId: config.appId, notes: config.notes }, log);
  } catch (e) {
    // Errors from the client already carry Apple's errors[].detail and never the token or headers.
    result = { ...failure(e instanceof Error ? e.message : "Unexpected error.", config.notes), dryRun: config.dryRun };
  }

  log(`${result.outcome.toUpperCase()}: ${result.message}`);
  deps.writeSummary(renderSummary(result));
  return result.outcome === "failed" ? 1 : 0;
}
