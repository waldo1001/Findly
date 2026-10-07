/** Domain types, decoupled from the JSON:API envelope (see parse.ts). */

export interface Build {
  id: string;
  /** CFBundleVersion, e.g. "240". */
  buildNumber: string;
  /** Marketing version from the build's preReleaseVersion, e.g. "1.2.0"; null if it could not be read. */
  marketingVersion: string | null;
  uploadedDate: string | null;
}

export interface AppVersion {
  id: string;
  versionString: string;
  /** appVersionState, falling back to the deprecated appStoreState; null if neither is present. */
  state: string | null;
  releaseType: string | null;
  /** ISO 8601, used to find the previous live version. */
  createdDate: string | null;
}

/** The build attached to a version. */
export interface BuildRef {
  id: string;
  buildNumber: string;
}

/** A review submission as listed (no items). */
export interface SubmissionRef {
  id: string;
  state: string;
}

export interface Localization {
  id: string;
  locale: string;
  whatsNew: string | null;
}

export interface ReviewDetail {
  demoAccountRequired: boolean | null;
  demoAccountName: string | null;
}

export interface OpenSubmission {
  id: string;
  /** appStoreVersion ids already in the submission. */
  versionIds: string[];
  /** Items that are not an App Store version (events, in-app purchases, …). */
  otherItemCount: number;
}
