import type { AppVersion, Build, BuildRef, Localization, OpenSubmission, ReviewDetail, SubmissionRef } from "./model";

/**
 * The pure heart of the release: state in, intended operations (or a stop/fail reason) out.
 * No I/O, so every branch is unit-tested against API-shaped fixtures (docs/store-readiness.md §5, iOS).
 */

export const RELEASE_TYPE_AFTER_APPROVAL = "AFTER_APPROVAL";
export const BUMP_HINT = "bump MARKETING_VERSION in mobile/ios/project.yml";
export const RESOLVE_HINT = "resolve or resubmit it in App Store Connect";

// appVersionState values (current) plus the deprecated appStoreState values that differ.
// https://developer.apple.com/documentation/appstoreconnectapi/appversionstate
// https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionstate
/** Live, or replaced by a newer live version: the marketing version cannot be reused. */
const LIVE_STATES = new Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION"]);
/** Strictly live right now (a replaced version is history). */
const CURRENTLY_LIVE_STATES = new Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION"]);
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

/** Review submission states (https://developer.apple.com/documentation/appstoreconnectapi/get-v1-reviewsubmissions). */
export const OPEN_SUBMISSION_STATE = "READY_FOR_REVIEW";
const BLOCKING_SUBMISSION_STATES = new Set(["UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW", "CANCELING", "COMPLETING"]);
/** Blocking, but resolves itself: say "wait and re-run", not "resolve it". */
const TRANSIENT_SUBMISSION_STATES = new Set(["CANCELING", "COMPLETING"]);
/** Every non-terminal state (COMPLETE is terminal): what the runner asks Apple for. */
export const NON_TERMINAL_SUBMISSION_STATES = [OPEN_SUBMISSION_STATE, ...BLOCKING_SUBMISSION_STATES];

export type Decision =
  | { kind: "fail"; message: string }
  /** `scope` "target": the build's own version is in flight. "other": a different version is, so this build cannot go yet. */
  | { kind: "stop"; scope: "target" | "other"; build: Build; version: AppVersion }
  | { kind: "create"; build: Build; previousLive: AppVersion | null }
  | { kind: "edit"; build: Build; version: AppVersion };

export interface Snapshot {
  build: Build | null;
  /** ALL App Store versions of the app on iOS: Apple allows one non-live version at a time. */
  versions: AppVersion[];
}

const rank = (state: string | null): number =>
  state === null ? 0 : LIVE_STATES.has(state) ? 3 : IN_FLIGHT_STATES.has(state) ? 2 : EDITABLE_STATES.has(state) ? 1 : 0;

const time = (v: AppVersion): number => (v.createdDate === null ? 0 : Date.parse(v.createdDate) || 0);

function newest(versions: AppVersion[]): AppVersion | null {
  return versions.reduce<AppVersion | null>((best, v) => (best === null || time(v) > time(best) ? v : best), null);
}

/** The newest version that is live now; failing that, the newest replaced one; null for a first release. */
function previousLiveVersion(versions: AppVersion[]): AppVersion | null {
  return (
    newest(versions.filter((v) => v.state !== null && CURRENTLY_LIVE_STATES.has(v.state))) ??
    newest(versions.filter((v) => v.state === "REPLACED_WITH_NEW_VERSION"))
  );
}

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
  const mv = build.marketingVersion;
  const label = `${mv} (build ${build.buildNumber})`;

  // 1. The build's own version.
  const matches = snapshot.versions.filter((v) => v.versionString === mv);
  // Several rows for one version string are unusual; act on the most advanced one.
  const own = matches.length === 0 ? null : matches.reduce((best, v) => (rank(v.state) > rank(best.state) ? v : best));
  if (own !== null) {
    const state = own.state;
    if (state === null) {
      return { kind: "fail", message: `Version ${label}: App Store Connect returned no version state; refusing to guess.` };
    }
    if (LIVE_STATES.has(state)) {
      return {
        kind: "fail",
        message:
          `Version ${mv} is already live or was replaced (state ${state}); build ${build.buildNumber} cannot ship under it. ` +
          `Nothing was changed. To release, ${BUMP_HINT}, then let CI upload a new build.`,
      };
    }
    if (IN_FLIGHT_STATES.has(state)) return { kind: "stop", scope: "target", build, version: own };
    if (!EDITABLE_STATES.has(state)) {
      return {
        kind: "fail",
        message:
          `Version ${label} is in state ${state}, which this release automation does not handle. ` +
          "Nothing was changed; resolve it in App Store Connect.",
      };
    }
  }

  // 2. Other versions: Apple allows one non-live version at a time, so another one in the way blocks this build.
  const others = snapshot.versions.filter((v) => v.versionString !== mv);
  const otherInFlight = others
    .filter((v) => v.state !== null && IN_FLIGHT_STATES.has(v.state))
    .reduce<AppVersion | null>((best, v) => (best === null || time(v) > time(best) ? v : best), null);
  if (otherInFlight !== null) return { kind: "stop", scope: "other", build, version: otherInFlight };
  const otherEditable = others.find((v) => v.state !== null && EDITABLE_STATES.has(v.state));
  if (otherEditable) {
    return {
      kind: "fail",
      message:
        `Version ${otherEditable.versionString} is still ${otherEditable.state} (an unsubmitted or rejected draft), so ${label} ` +
        "cannot be submitted: App Store Connect allows one non-live version at a time. " +
        "Nothing was changed; submit or remove that version in App Store Connect first.",
    };
  }

  if (own !== null) return { kind: "edit", build, version: own };
  return { kind: "create", build, previousLive: previousLiveVersion(snapshot.versions) };
}

/** Human-readable stop reason, naming the build actually attached to the in-flight version. */
export function describeStop(args: { build: Build; version: AppVersion; scope: "target" | "other"; attached: BuildRef | null }): string {
  const { build, version, scope, attached } = args;
  const v = `${version.versionString}`;
  const state = version.state ?? "UNKNOWN";
  const buildPart = attached === null ? "it could not be determined which build is attached" : `build ${attached.buildNumber} attached`;
  if (scope === "other") {
    return (
      `Version ${v} is ${state} (${buildPart}). The newest processed build is ${build.marketingVersion} (build ${build.buildNumber}), ` +
      "which cannot be submitted while another version is in flight. Nothing was submitted; no changes made."
    );
  }
  if (attached === null) {
    return (
      `Version ${v} is already ${state}, but it could not be determined which build is attached. ` +
      `The newest processed build is ${build.buildNumber}. Nothing was submitted; no changes made.`
    );
  }
  if (attached.id !== build.id) {
    return (
      `Version ${v} is already ${state} with build ${attached.buildNumber} attached; the newest processed build ` +
      `(${build.buildNumber}) is not the one in review. Nothing was submitted; no changes made.`
    );
  }
  return `Version ${v} (build ${attached.buildNumber}) is already ${state}. Nothing to submit; no changes made.`;
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

export type EditPlan = { kind: "ops"; ops: Op[] } | { kind: "fail"; message: string };

/** First blocking review submission (UNRESOLVED_ISSUES, WAITING_FOR_REVIEW, IN_REVIEW, CANCELING, COMPLETING), as a failure message. */
export function checkSubmissions(submissions: SubmissionRef[]): string | null {
  const blocking = submissions.find((s) => BLOCKING_SUBMISSION_STATES.has(s.state));
  if (!blocking) return null;
  if (TRANSIENT_SUBMISSION_STATES.has(blocking.state)) {
    // Apple is still finishing it (canceling / completing): nothing for a human to resolve.
    return `Review submission ${blocking.id} is ${blocking.state}, which Apple is still processing; wait a few minutes and re-run.`;
  }
  return `Review submission ${blocking.id} is ${blocking.state}; ${RESOLVE_HINT}. Submitting now could clash with it.`;
}

/** What is wrong with the App Review details (never includes the account name): nothing, no resource, or no demo account. */
function reviewDetailGap(detail: ReviewDetail | null): "missing" | "no-demo-account" | null {
  if (detail === null) return "missing";
  if (detail.demoAccountRequired !== true || (detail.demoAccountName ?? "").trim() === "") return "no-demo-account";
  return null;
}

/** Failure message for an editable version, where the operator can fix its App Review information directly. */
function reviewDetailProblem(detail: ReviewDetail | null, subject: string): string | null {
  const gap = reviewDetailGap(detail);
  if (gap === "missing") {
    return (
      `${subject.charAt(0).toUpperCase()}${subject.slice(1)} has no App Review information. Open it in App Store Connect and fill in App Review ` +
      "(sign-in required, demo account); the automation will not invent one."
    );
  }
  if (gap === "no-demo-account") {
    return (
      `App Review information for ${subject} does not include a demo account (sign-in required, with a ` +
      "demo account name). Set it in App Store Connect; the automation will not invent one."
    );
  }
  return null;
}

/** Prefer the open draft that already holds the version, otherwise the first one. */
export function chooseOpenSubmission(drafts: OpenSubmission[], versionId: string): OpenSubmission | null {
  return drafts.find((s) => s.versionIds.includes(versionId)) ?? drafts[0] ?? null;
}

/**
 * The version does not exist yet. Check every blocker that does not need it, so a dry run (and a live run,
 * before the POST) fail early; the App Review check after creation stays authoritative.
 */
export function planCreate(args: {
  appId: string;
  build: Build;
  submissions: SubmissionRef[];
  drafts: OpenSubmission[];
  previousLive: AppVersion | null;
  /** App Review details of `previousLive` (the proxy); ignored when there is no previous live version. */
  proxyReviewDetail: ReviewDetail | null;
}): EditPlan {
  const blocked = checkSubmissions(args.submissions);
  if (blocked !== null) return { kind: "fail", message: blocked };
  const loaded = args.drafts.find((d) => d.versionIds.length > 0 || d.otherItemCount > 0);
  if (loaded) {
    return {
      kind: "fail",
      message:
        `The open review submission ${loaded.id} already contains other items, and submitting it would send them too. ` +
        "Review it in App Store Connect.",
    };
  }
  if (args.previousLive !== null) {
    const gap = reviewDetailGap(args.proxyReviewDetail);
    if (gap !== null) {
      const live = args.previousLive.versionString;
      const next = args.build.marketingVersion ?? "the new version";
      const what =
        gap === "missing"
          ? "has no App Review information"
          : "has no demo account in its App Review information (sign-in required, with a demo account name)";
      return {
        kind: "fail",
        // A live version is read-only: the fix belongs on the NEW version, not the old one.
        message:
          `The previous live version ${live} ${what}, and a new version inherits it. A live version is read-only, so it cannot be fixed there. ` +
          `Create version ${next} in App Store Connect, fill in its App Review information (sign-in required, demo account), ` +
          "then re-run: the run then takes the edit path, where this check is authoritative. The automation will not invent a demo account.",
      };
    }
  }
  return { kind: "ops", ops: [{ kind: "createVersion", appId: args.appId, versionString: args.build.marketingVersion ?? "" }] };
}

export interface Details {
  localizations: Localization[];
  attachedBuildId: string | null;
  reviewDetail: ReviewDetail | null;
  phasedReleaseId: string | null;
  /** Every non-terminal review submission of the app. */
  submissions: SubmissionRef[];
  /** The READY_FOR_REVIEW drafts among them, with their items. */
  drafts: OpenSubmission[];
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
  const blocked = checkSubmissions(details.submissions);
  if (blocked !== null) return { kind: "fail", message: blocked };

  const problem = reviewDetailProblem(details.reviewDetail, `version ${version.versionString}`);
  if (problem !== null) return { kind: "fail", message: problem };

  if (details.localizations.length === 0) {
    return {
      kind: "fail",
      message: `Version ${version.versionString} has no localizations, so there is nowhere to set What's New.`,
    };
  }
  const open = chooseOpenSubmission(details.drafts, version.id);
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
