import type { AppVersion, Build, Localization, OpenSubmission, ReviewDetail } from "./model";

/**
 * The pure heart of the release: state in, intended operations (or a stop/fail reason) out.
 * No I/O, so every branch is unit-tested against API-shaped fixtures (docs/store-readiness.md §5, iOS).
 */

export const RELEASE_TYPE_AFTER_APPROVAL = "AFTER_APPROVAL";
export const BUMP_HINT = "bump MARKETING_VERSION in mobile/ios/project.yml";

// appVersionState values (current) plus the deprecated appStoreState values that differ.
// https://developer.apple.com/documentation/appstoreconnectapi/appversionstate
// https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionstate
/** Already shipped: the marketing version cannot be reused. */
const LIVE_STATES = new Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION"]);
/** Submitted, in review, approved or being processed: nothing to do, change nothing. */
const IN_FLIGHT_STATES = new Set([
  "WAITING_FOR_REVIEW",
  "IN_REVIEW",
  "PENDING_DEVELOPER_RELEASE",
  "PENDING_APPLE_RELEASE",
  "ACCEPTED",
  "PROCESSING_FOR_DISTRIBUTION",
  "PROCESSING_FOR_APP_STORE",
]);
/** The version can still be edited and (re)submitted. */
const EDITABLE_STATES = new Set([
  "PREPARE_FOR_SUBMISSION",
  "READY_FOR_REVIEW",
  "DEVELOPER_REJECTED",
  "METADATA_REJECTED",
  "REJECTED",
  "INVALID_BINARY",
]);

export type Decision =
  | { kind: "fail"; message: string }
  | { kind: "stop"; message: string; build: Build; version: AppVersion }
  | { kind: "create"; build: Build }
  | { kind: "edit"; build: Build; version: AppVersion };

export interface Snapshot {
  build: Build | null;
  /** App Store versions of the app on iOS (any version string; matched here). */
  versions: AppVersion[];
}

const rank = (state: string | null): number =>
  state === null ? 0 : LIVE_STATES.has(state) ? 3 : IN_FLIGHT_STATES.has(state) ? 2 : EDITABLE_STATES.has(state) ? 1 : 0;

export function decide(snapshot: Snapshot): Decision {
  const { build } = snapshot;
  if (build === null) {
    return {
      kind: "fail",
      message:
        "No processed build found: App Store Connect has no build with processingState VALID for com.findly.ios. " +
        "Upload one (the ios workflow publishes to TestFlight on push to main) and wait for processing.",
    };
  }
  if (build.marketingVersion === null) {
    return {
      kind: "fail",
      message: `Build ${build.buildNumber} has no readable marketing version (its preReleaseVersion was not returned).`,
    };
  }
  const label = `${build.marketingVersion} (build ${build.buildNumber})`;

  const matches = snapshot.versions.filter((v) => v.versionString === build.marketingVersion);
  if (matches.length === 0) return { kind: "create", build };

  // Several rows for one version string are unusual; act on the most advanced one.
  const version = matches.reduce((best, v) => (rank(v.state) > rank(best.state) ? v : best));
  const state = version.state;

  if (state === null) {
    return { kind: "fail", message: `Version ${label}: App Store Connect returned no version state; refusing to guess.` };
  }
  if (LIVE_STATES.has(state)) {
    return {
      kind: "fail",
      message:
        `Version ${build.marketingVersion} is already live or was replaced (state ${state}); build ${build.buildNumber} cannot ship under it. ` +
        `Nothing was changed. To release, ${BUMP_HINT}, then let CI upload a new build.`,
    };
  }
  if (IN_FLIGHT_STATES.has(state)) {
    return {
      kind: "stop",
      build,
      version,
      message: `Version ${label} is already ${state}. Nothing to submit; no changes made.`,
    };
  }
  if (EDITABLE_STATES.has(state)) return { kind: "edit", build, version };
  return {
    kind: "fail",
    message:
      `Version ${label} is in state ${state}, which this release automation does not handle. ` +
      "Nothing was changed; resolve it in App Store Connect.",
  };
}

export type Op =
  | { kind: "createVersion"; appId: string; versionString: string }
  | { kind: "setWhatsNew"; localizationId: string; locale: string; text: string }
  | { kind: "attachBuild"; versionId: string; buildId: string; buildNumber: string }
  | { kind: "setReleaseType"; versionId: string; releaseType: typeof RELEASE_TYPE_AFTER_APPROVAL; from: string | null }
  | { kind: "deletePhasedRelease"; phasedReleaseId: string }
  | { kind: "createReviewSubmission"; appId: string }
  /** `submissionId: null` = the submission created earlier in the same plan. */
  | { kind: "addSubmissionItem"; submissionId: string | null; versionId: string }
  | { kind: "submitReviewSubmission"; submissionId: string | null };

export function planCreate(args: { appId: string; build: Build }): Op[] {
  return [{ kind: "createVersion", appId: args.appId, versionString: args.build.marketingVersion ?? "" }];
}

export interface Details {
  localizations: Localization[];
  attachedBuildId: string | null;
  reviewDetail: ReviewDetail | null;
  phasedReleaseId: string | null;
  openSubmission: OpenSubmission | null;
}

export type EditPlan = { kind: "ops"; ops: Op[] } | { kind: "fail"; message: string };

/** Prefer the open submission that already holds the version, otherwise the first one. */
export function chooseOpenSubmission(open: OpenSubmission[], versionId: string): OpenSubmission | null {
  return open.find((s) => s.versionIds.includes(versionId)) ?? open[0] ?? null;
}

export function planEdit(args: {
  appId: string;
  notes: string;
  build: Build;
  version: AppVersion;
  details: Details;
}): EditPlan {
  const { appId, notes, build, version, details } = args;

  // Validate everything that could make us stop BEFORE emitting a single change.
  const review = details.reviewDetail;
  if (review === null) {
    return {
      kind: "fail",
      message:
        `Version ${version.versionString} has no App Review information. Open it in App Store Connect and fill in App Review ` +
        "(sign-in required, demo account); the automation will not invent one.",
    };
  }
  if (review.demoAccountRequired !== true || (review.demoAccountName ?? "").trim() === "") {
    return {
      kind: "fail",
      message:
        `App Review information for ${version.versionString} does not include a demo account (sign-in required, with a ` +
        "demo account name). Set it in App Store Connect; the automation will not invent one.",
    };
  }
  if (details.localizations.length === 0) {
    return {
      kind: "fail",
      message: `Version ${version.versionString} has no localizations, so there is nowhere to set What's New.`,
    };
  }
  const open = details.openSubmission;
  if (open !== null && (open.otherItemCount > 0 || open.versionIds.some((id) => id !== version.id))) {
    return {
      kind: "fail",
      message:
        `The open review submission ${open.id} contains other items besides version ${version.versionString}; ` +
        "submitting it would send them too. Review it in App Store Connect.",
    };
  }

  const ops: Op[] = [];
  for (const loc of details.localizations) {
    if ((loc.whatsNew ?? "").trim() !== notes) {
      ops.push({ kind: "setWhatsNew", localizationId: loc.id, locale: loc.locale, text: notes });
    }
  }
  if (details.attachedBuildId !== build.id) {
    ops.push({ kind: "attachBuild", versionId: version.id, buildId: build.id, buildNumber: build.buildNumber });
  }
  if (version.releaseType !== RELEASE_TYPE_AFTER_APPROVAL) {
    ops.push({
      kind: "setReleaseType",
      versionId: version.id,
      releaseType: RELEASE_TYPE_AFTER_APPROVAL,
      from: version.releaseType,
    });
  }
  if (details.phasedReleaseId !== null) {
    ops.push({ kind: "deletePhasedRelease", phasedReleaseId: details.phasedReleaseId });
  }
  if (open === null) {
    ops.push({ kind: "createReviewSubmission", appId });
    ops.push({ kind: "addSubmissionItem", submissionId: null, versionId: version.id });
    ops.push({ kind: "submitReviewSubmission", submissionId: null });
  } else {
    if (!open.versionIds.includes(version.id)) {
      ops.push({ kind: "addSubmissionItem", submissionId: open.id, versionId: version.id });
    }
    ops.push({ kind: "submitReviewSubmission", submissionId: open.id });
  }
  return { kind: "ops", ops };
}

/** One-line, secret-free description of an operation, for the job log and the step summary. */
export function describeOp(op: Op): string {
  switch (op.kind) {
    case "createVersion":
      return `Create App Store version ${op.versionString} (release type ${RELEASE_TYPE_AFTER_APPROVAL})`;
    case "setWhatsNew":
      return `Set What's New (${op.locale}, ${op.text.length} characters)`;
    case "attachBuild":
      return `Attach build ${op.buildNumber} to the version`;
    case "setReleaseType":
      return `Set release type ${op.from ?? "(unset)"} -> ${op.releaseType}`;
    case "deletePhasedRelease":
      return "Remove the phased release";
    case "createReviewSubmission":
      return "Create a review submission (iOS)";
    case "addSubmissionItem":
      return `Add the version to ${op.submissionId === null ? "the new" : "the open"} review submission`;
    case "submitReviewSubmission":
      return `Submit ${op.submissionId === null ? "the new" : "the open"} review submission to App Review`;
  }
}
