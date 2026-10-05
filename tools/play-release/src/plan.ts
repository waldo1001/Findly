// The pure planner (docs/store-readiness.md §5, Android steps 1-4). No I/O, no clock, no
// randomness: track + listing data in, a decision out. Everything that talks to Play lives in
// play-client.ts / release.ts; keeping the decision logic here is what makes it unit-testable
// against JSON fixtures shaped like real `edits.tracks.get` responses.

/** Play's per-language release-notes limit. */
export const MAX_NOTES_LENGTH = 500;

/** The language every release carries notes for, whatever the store listing contains. */
export const DEFAULT_LANGUAGE = "en-GB";

export interface ReleaseNote {
  language: string;
  text: string;
}

/** A release as `edits.tracks.get` returns it (only the fields the planner reads). */
export interface Release {
  name?: string;
  /** int64 values — the API serialises them as strings. */
  versionCodes?: string[];
  status?: string;
  userFraction?: number;
  releaseNotes?: ReleaseNote[];
}

export interface Track {
  track?: string;
  /** Absent (not `[]`) on a track that has never had a release. */
  releases?: Release[];
}

/** The release the planner asks Play to set: a full, plain `completed` rollout. */
export interface PlannedRelease {
  versionCodes: string[];
  status: "completed";
  releaseNotes: ReleaseNote[];
}

/** Request body for `edits.tracks.update`. */
export interface TrackBody {
  track: string;
  releases: PlannedRelease[];
}

export interface PlanInput {
  internal?: Track | undefined;
  production?: Track | undefined;
  alpha?: Track | undefined;
}

export type PlanErrorCode =
  | "notes-empty"
  | "notes-too-long"
  | "no-internal-release"
  | "production-ahead"
  | "production-halted"
  | "production-rollout-ahead";

export interface PlanError {
  action: "error";
  code: PlanErrorCode;
  message: string;
}

export interface PlanNothing {
  action: "nothing";
  versionCodes: string[];
  /** Name of Internal's release (e.g. "1.2.0 (234)"), when Play gives one. */
  name?: string | undefined;
  /** Version codes of the current completed release on each track ([] when none). */
  production: string[];
  alpha: string[];
}

export interface PlanRelease {
  action: "release";
  versionCodes: string[];
  /** Name of Internal's release (e.g. "1.2.0 (234)"), when Play gives one. */
  name?: string | undefined;
  languages: string[];
  /** The trimmed notes, identical for every language. */
  notes: string;
  bodies: { production: TrackBody; alpha: TrackBody };
  before: { production: string[]; alpha: string[] };
}

export type Plan = PlanError | PlanNothing | PlanRelease;

export type NotesResult = { ok: true; text: string } | { ok: false; error: PlanError };

/** Trim and validate the release notes. Exported so callers can fail before touching the network. */
export function checkNotes(raw: string | undefined): NotesResult {
  const text = (raw ?? "").trim();
  if (text === "") {
    return {
      ok: false,
      error: { action: "error", code: "notes-empty", message: "Release notes are empty. Provide the text to show users." },
    };
  }
  // `.length` counts UTF-16 units — never fewer than the characters a user sees, so this can only
  // be stricter than Play, never looser. Play's own `validate` is the backstop either way.
  if (text.length > MAX_NOTES_LENGTH) {
    return {
      ok: false,
      error: {
        action: "error",
        code: "notes-too-long",
        message: `Release notes are ${text.length} characters; Play allows at most ${MAX_NOTES_LENGTH} per language. Shorten them and run again.`,
      },
    };
  }
  return { ok: true, text };
}

function byNumericValue(a: string, b: string): number {
  return Number(a) - Number(b);
}

/**
 * The version codes of a track's *current* completed release: of all `completed` releases that
 * carry version codes, the one holding the highest code. `undefined` when there is none.
 * Draft, halted and inProgress releases never count.
 */
function currentCompleted(track: Track | undefined): string[] | undefined {
  let best: string[] | undefined;
  let bestMax = -Infinity;
  for (const release of track?.releases ?? []) {
    if (release.status !== "completed" || !release.versionCodes?.length) continue;
    const codes = [...new Set(release.versionCodes)].sort(byNumericValue);
    const max = Number(codes[codes.length - 1]);
    if (max > bestMax) {
      best = codes;
      bestMax = max;
    }
  }
  return best;
}

function sameCodes(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((code, i) => code === b[i]);
}

function maxCode(codes: string[]): number {
  return Math.max(...codes.map(Number));
}

export function plan(tracks: PlanInput, listingLanguages: string[], rawNotes: string | undefined): Plan {
  const notes = checkNotes(rawNotes);
  if (!notes.ok) return notes.error;

  const internal = currentCompleted(tracks.internal);
  if (!internal) {
    return {
      action: "error",
      code: "no-internal-release",
      message:
        "The Internal testing track has no completed release to promote. Upload a build to Internal testing first.",
    };
  }

  const production = currentCompleted(tracks.production) ?? [];
  const alpha = currentCompleted(tracks.alpha) ?? [];

  if (sameCodes(internal, production)) {
    return { action: "nothing", versionCodes: internal, production, alpha };
  }

  // Safety net, not in the spec: releasing a lower version code than production already serves
  // is a downgrade attempt, never what a promote means. Fail closed, change nothing.
  if (production.length > 0 && maxCode(production) > maxCode(internal)) {
    return {
      action: "error",
      code: "production-ahead",
      message: `Production already serves version code ${maxCode(production)}, newer than Internal testing's ${maxCode(internal)}. Refusing to release a downgrade.`,
    };
  }

  const languages = [...new Set([DEFAULT_LANGUAGE, ...listingLanguages])];
  const releaseNotes = languages.map((language) => ({ language, text: notes.text }));
  const body = (track: string): TrackBody => ({
    track,
    releases: [{ versionCodes: [...internal], status: "completed", releaseNotes: releaseNotes.map((n) => ({ ...n })) }],
  });

  return {
    action: "release",
    versionCodes: internal,
    languages,
    notes: notes.text,
    bodies: { production: body("production"), alpha: body("alpha") },
    before: { production, alpha },
  };
}
