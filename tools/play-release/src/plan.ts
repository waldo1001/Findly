// RED stub — types only, behaviour arrives in the green commit.

export const MAX_NOTES_LENGTH = 500;

export interface ReleaseNote {
  language: string;
  text: string;
}

export interface Release {
  name?: string;
  versionCodes?: string[];
  status?: string;
  userFraction?: number;
  releaseNotes?: ReleaseNote[];
}

export interface Track {
  track?: string;
  releases?: Release[];
}

export interface PlannedRelease {
  versionCodes: string[];
  status: "completed";
  releaseNotes: ReleaseNote[];
}

export interface TrackBody {
  track: string;
  releases: PlannedRelease[];
}

export interface PlanInput {
  internal?: Track | undefined;
  production?: Track | undefined;
  alpha?: Track | undefined;
}

export type PlanErrorCode = "notes-empty" | "notes-too-long" | "no-internal-release" | "production-ahead";

export interface PlanError {
  action: "error";
  code: PlanErrorCode;
  message: string;
}

export interface PlanNothing {
  action: "nothing";
  versionCodes: string[];
  production: string[];
  alpha: string[];
}

export interface PlanRelease {
  action: "release";
  versionCodes: string[];
  languages: string[];
  notes: string;
  bodies: { production: TrackBody; alpha: TrackBody };
  before: { production: string[]; alpha: string[] };
}

export type Plan = PlanError | PlanNothing | PlanRelease;

export function plan(_tracks: PlanInput, _listingLanguages: string[], _notes: string | undefined): Plan {
  throw new Error("not implemented");
}
