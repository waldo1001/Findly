import { normalizePrivateKey } from "./jwt";

/** Findly's App Store Connect app (docs/h6-apple-portal-runbook.md Step 3): `com.findly.ios`. */
export const APP_APPLE_ID = "6797994768";
/** Play's release-notes limit; the same text goes to both stores, so a `both` run can never split. */
export const MAX_NOTES_LENGTH = 500;

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

export interface Config {
  keyId: string;
  issuerId: string;
  /** PEM, decoded from ASC_API_KEY_P8. Held in memory only; never written to disk or logged. */
  privateKey: string;
  notes: string;
  dryRun: boolean;
  appId: string;
}

/** Trim; reject empty or longer than {@link MAX_NOTES_LENGTH} (Apple itself allows 4000). */
export function parseNotes(raw: string | undefined): string {
  const notes = (raw ?? "").trim();
  if (notes === "") throw new ConfigError("RELEASE_NOTES must not be empty.");
  if (notes.length > MAX_NOTES_LENGTH) {
    throw new ConfigError(`RELEASE_NOTES is ${notes.length} characters; App Store Connect allows at most ${MAX_NOTES_LENGTH}.`);
  }
  return notes;
}

/** Strict on purpose: a typo or an unset variable must never silently become a live release. */
export function parseDryRun(raw: string | undefined): boolean {
  const v = (raw ?? "").trim().toLowerCase();
  if (v === "true") return true;
  if (v === "false") return false;
  throw new ConfigError("DRY_RUN must be exactly 'true' or 'false' (refusing to guess).");
}

const REQUIRED = ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_API_KEY_P8"] as const;

/** Reads everything from the environment. Error messages name variables, never values. */
export function loadConfig(env: Record<string, string | undefined>): Config {
  const problems: string[] = [];
  const missing = REQUIRED.filter((name) => (env[name] ?? "").trim() === "");
  if (missing.length > 0) problems.push(`Missing required environment variable(s): ${missing.join(", ")}.`);

  let dryRun = true;
  try {
    dryRun = parseDryRun(env.DRY_RUN);
  } catch (e) {
    problems.push((e as Error).message);
  }

  let notes = "";
  try {
    notes = parseNotes(env.RELEASE_NOTES);
  } catch (e) {
    problems.push((e as Error).message);
  }

  let privateKey = "";
  if (!missing.includes("ASC_API_KEY_P8")) {
    try {
      privateKey = normalizePrivateKey(env.ASC_API_KEY_P8 ?? "");
    } catch (e) {
      problems.push((e as Error).message);
    }
  }

  if (problems.length > 0) throw new ConfigError(problems.join(" "));
  return {
    keyId: (env.ASC_KEY_ID ?? "").trim(),
    issuerId: (env.ASC_ISSUER_ID ?? "").trim(),
    privateKey,
    notes,
    dryRun,
    appId: APP_APPLE_ID,
  };
}
