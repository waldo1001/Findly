import type { AscClient, JsonApiDoc, JsonApiResource } from "./http";
import type { AppVersion, OpenSubmission, SubmissionRef } from "./model";
import {
  parseBuildRef,
  parseLinkageId,
  parseLocalizations,
  parseNewestBuild,
  parseOpenSubmission,
  parseReviewDetail,
  parseSubmissions,
  parseVersions,
} from "./parse";
import {
  NON_TERMINAL_SUBMISSION_STATES,
  OPEN_SUBMISSION_STATE,
  RELEASE_TYPE_AFTER_APPROVAL,
  decide,
  describeOp,
  describeStop,
  planCreate,
  planEdit,
  type Details,
  type Op,
} from "./planner";

/**
 * Orchestrates one release: read state -> decide -> (check blockers, create the version) -> read details ->
 * plan -> execute -> read the resulting state. All store access goes through the injected {@link AscClient},
 * which refuses non-GET requests in dry-run mode.
 *
 * Endpoints (https://developer.apple.com/documentation/appstoreconnectapi/…):
 *   GET   /v1/builds                                     get-v1-builds
 *   GET   /v1/apps/{id}/appStoreVersions                 get-v1-apps-_id_-appstoreversions (ALL iOS versions)
 *   GET   /v1/appStoreVersions/{id}/build                get-v1-appstoreversions-_id_-build (stop reporting)
 *   POST  /v1/appStoreVersions                           post-v1-appstoreversions
 *   GET   /v1/appStoreVersions/{id}/appStoreVersionLocalizations
 *   PATCH /v1/appStoreVersionLocalizations/{id}          patch-v1-appstoreversionlocalizations-_id_
 *   GET   /v1/appStoreVersions/{id}/relationships/build  get-v1-appstoreversions-_id_-relationships-build
 *   PATCH /v1/appStoreVersions/{id}/relationships/build  patch-v1-appstoreversions-_id_-relationships-build
 *   PATCH /v1/appStoreVersions/{id}                      patch-v1-appstoreversions-_id_
 *   GET   /v1/appStoreVersions/{id}/appStoreReviewDetail get-v1-appstoreversions-_id_-appstorereviewdetail
 *   GET   /v1/appStoreVersions/{id}/relationships/appStoreVersionPhasedRelease
 *   DELETE /v1/appStoreVersionPhasedReleases/{id}        delete-v1-appstoreversionphasedreleases-_id_
 *   GET   /v1/reviewSubmissions, GET /v1/reviewSubmissions/{id}/items
 *   POST  /v1/reviewSubmissions, POST /v1/reviewSubmissionItems, PATCH /v1/reviewSubmissions/{id}
 */

export interface Step {
  description: string;
  status: "planned" | "done" | "failed" | "skipped";
}

export interface ReleaseResult {
  outcome: "submitted" | "dry-run" | "stopped" | "failed";
  dryRun: boolean;
  /** One human-readable paragraph: the reason for a stop/failure, or what happened. */
  message: string;
  version: string | null;
  buildNumber: string | null;
  stateBefore: string | null;
  stateAfter: string | null;
  steps: Step[];
  notes: string;
}

export interface ReleaseInput {
  appId: string;
  notes: string;
}

const NO_CHANGES = "No changes were made.";
/** Resource ids come from API responses: always percent-encode them into a path segment. */
const seg = encodeURIComponent;
const REVIEW_DETAIL_FIELDS = { "fields[appStoreReviewDetails]": "demoAccountRequired,demoAccountName" };

interface Ctx {
  version: string | null;
  buildNumber: string | null;
  stateBefore: string | null;
  steps: Step[];
  /** The version string of a draft this run created, once it has. */
  createdDraft: string | null;
}

export async function runRelease(client: AscClient, input: ReleaseInput, log: (line: string) => void): Promise<ReleaseResult> {
  const ctx: Ctx = { version: null, buildNumber: null, stateBefore: null, steps: [], createdDraft: null };
  const finish = (r: Partial<ReleaseResult> & Pick<ReleaseResult, "outcome" | "message">): ReleaseResult => ({
    dryRun: client.dryRun,
    version: ctx.version,
    buildNumber: ctx.buildNumber,
    stateBefore: ctx.stateBefore,
    stateAfter: null,
    steps: ctx.steps,
    notes: input.notes,
    ...r,
  });
  /** A failure, with an honest account of what had (not) been changed by then. */
  const failed = (message: string): ReleaseResult =>
    finish({
      outcome: "failed",
      message:
        ctx.createdDraft !== null
          ? `${message} The draft version ${ctx.createdDraft} was created earlier in this run and was not rolled back; re-running the workflow is safe.`
          : ctx.steps.some((s) => s.status === "done")
            ? `${message} Steps already completed were not rolled back; re-running the workflow is safe.`
            : `${message} ${NO_CHANGES}`,
    });

  try {
    return await run(client, input, log, ctx, finish, failed);
  } catch (e) {
    // Errors from the client already carry Apple's errors[].detail and never the token or headers.
    return failed(e instanceof Error ? e.message : "Unexpected error.");
  }
}

async function run(
  client: AscClient,
  input: ReleaseInput,
  log: (line: string) => void,
  ctx: Ctx,
  finish: (r: Partial<ReleaseResult> & Pick<ReleaseResult, "outcome" | "message">) => ReleaseResult,
  failed: (message: string) => ReleaseResult,
): Promise<ReleaseResult> {
  const { appId, notes } = input;

  log(client.dryRun ? "DRY RUN: only GET requests will be sent." : "LIVE RUN: changes will be made in App Store Connect.");

  log("Looking up the newest processed build...");
  const build = parseNewestBuild(
    await client.get<JsonApiDoc<JsonApiResource[]>>("/v1/builds", {
      "filter[app]": appId,
      "filter[processingState]": "VALID",
      // Internal-only (TestFlight-only) builds cannot be attached to an App Store version.
      "filter[buildAudienceType]": "APP_STORE_ELIGIBLE",
      "filter[preReleaseVersion.platform]": "IOS",
      "filter[expired]": "false",
      sort: "-uploadedDate",
      include: "preReleaseVersion",
      limit: "1",
    }),
  );
  if (build) {
    ctx.version = build.marketingVersion;
    ctx.buildNumber = build.buildNumber;
    log(`Newest processed build: ${build.marketingVersion ?? "(unknown version)"} (${build.buildNumber}).`);
  }

  let versions: AppVersion[] = [];
  if (build?.marketingVersion) {
    // ALL iOS versions, not just this build's: Apple allows one non-live version at a time.
    log("Listing the app's iOS versions...");
    const all = await client.getAll<JsonApiResource>(`/v1/apps/${seg(appId)}/appStoreVersions`, {
      "filter[platform]": "IOS",
      limit: "200",
    });
    versions = parseVersions({ data: all.data });
  }

  const decision = decide({ build, versions });

  if (decision.kind === "fail") return failed(decision.message);

  if (decision.kind === "stop") {
    const attached = parseBuildRef(
      await client.getOptional(`/v1/appStoreVersions/${seg(decision.version.id)}/build`, { "fields[builds]": "version" }),
    );
    const message = describeStop({ build: decision.build, version: decision.version, scope: decision.scope, attached });
    ctx.version = decision.version.versionString;
    ctx.buildNumber = attached?.buildNumber ?? null;
    ctx.stateBefore = decision.version.state;
    log(message);
    return finish({ outcome: "stopped", message });
  }

  let version: AppVersion;
  let subs: { refs: SubmissionRef[]; drafts: OpenSubmission[] };

  if (decision.kind === "create") {
    const mv = decision.build.marketingVersion ?? "";
    // Everything that can block, before the first change: other versions (decide), review submissions, and the
    // previous live version's App Review details as a proxy. The check after creation stays authoritative.
    subs = await readSubmissions(client, appId);
    const previousLive = decision.previousLive;
    const proxyReviewDetail =
      previousLive === null
        ? null
        : parseReviewDetail(
            await client.getOptional(`/v1/appStoreVersions/${seg(previousLive.id)}/appStoreReviewDetail`, REVIEW_DETAIL_FIELDS),
          );
    const createPlan = planCreate({
      appId,
      build: decision.build,
      submissions: subs.refs,
      drafts: subs.drafts,
      previousLive,
      proxyReviewDetail,
    });
    if (createPlan.kind === "fail") return failed(createPlan.message);
    const create = createPlan.ops[0]!;

    if (client.dryRun) {
      return finish({
        outcome: "dry-run",
        message:
          `Version ${mv} does not exist in App Store Connect yet. No blockers found (other versions, review submissions` +
          `${previousLive === null ? "" : `, and the previous live version ${previousLive.versionString}'s App Review details as a proxy`}). ` +
          `A live run would create it, then plan the remaining steps from its real state. ${NO_CHANGES}`,
        steps: [
          { description: describeOp(create), status: "planned" },
          {
            description:
              "After the version exists: set What's New on every localization, attach the build, verify the new version's App Review " +
              "details (sign-in required, demo account), and submit for review",
            status: "planned",
          },
        ],
      });
    }

    log(describeOp(create));
    const created = await client.post<JsonApiDoc<JsonApiResource>>("/v1/appStoreVersions", {
      data: {
        type: "appStoreVersions",
        attributes: { platform: "IOS", versionString: mv, releaseType: RELEASE_TYPE_AFTER_APPROVAL },
        relationships: { app: { data: { type: "apps", id: appId } } },
      },
    });
    ctx.createdDraft = mv;
    ctx.steps.push({ description: describeOp(create), status: "done" });
    const [createdVersion] = parseVersions({ data: [created.data] });
    const again = decide({ build: decision.build, versions: createdVersion ? [createdVersion] : [] });
    if (again.kind !== "edit") {
      return failed(again.kind === "fail" ? again.message : "The created version could not be read back in an editable state.");
    }
    version = again.version;
    ctx.stateBefore = version.state;
  } else {
    version = decision.version;
    ctx.stateBefore = version.state;
    subs = { refs: [], drafts: [] }; // read below, after the version details
  }

  log(`Version ${version.versionString} is ${version.state}; reading its details...`);
  const base = await readDetails(client, version);
  if (decision.kind === "edit") subs = await readSubmissions(client, appId);
  const details: Details = { ...base, submissions: subs.refs, drafts: subs.drafts };
  const plan = planEdit({ appId, notes, build: decision.build, version, details });
  if (plan.kind === "fail") return failed(plan.message);

  if (client.dryRun) {
    const planned: Step[] = plan.ops.map((op) => ({ description: describeOp(op), status: "planned" }));
    for (const s of planned) log(`Would: ${s.description}`);
    return finish({
      outcome: "dry-run",
      message: `Dry run: ${plan.ops.length} change(s) would be made to submit ${version.versionString} (build ${decision.build.buildNumber}). ${NO_CHANGES}`,
      steps: planned,
    });
  }

  const failure = await executeOps(client, plan.ops, ctx.steps, log);
  if (failure !== null) return failed(failure);

  let stateAfter: string | null = null;
  try {
    const doc = await client.get<JsonApiDoc<JsonApiResource>>(`/v1/appStoreVersions/${seg(version.id)}`);
    stateAfter = parseVersions({ data: [doc.data] })[0]?.state ?? null;
  } catch {
    log("Submitted, but the version state could not be read back.");
  }
  return finish({
    outcome: "submitted",
    message: `Submitted ${version.versionString} (build ${decision.build.buildNumber}) for App Review.`,
    stateAfter,
  });
}

async function readDetails(client: AscClient, version: AppVersion): Promise<Omit<Details, "submissions" | "drafts">> {
  const base = `/v1/appStoreVersions/${seg(version.id)}`;
  const localizations = parseLocalizations(
    await client.getAll<JsonApiResource>(`${base}/appStoreVersionLocalizations`, {
      "fields[appStoreVersionLocalizations]": "locale,whatsNew",
      limit: "200",
    }),
  );
  const attachedBuildId = parseLinkageId(await client.getOptional(`${base}/relationships/build`));
  // Only what the check needs: the demo account's password is never requested, so it never enters memory.
  const reviewDetail = parseReviewDetail(await client.getOptional(`${base}/appStoreReviewDetail`, REVIEW_DETAIL_FIELDS));
  const phasedReleaseId = parseLinkageId(await client.getOptional(`${base}/relationships/appStoreVersionPhasedRelease`));
  return { localizations, attachedBuildId, reviewDetail, phasedReleaseId };
}

/** Every non-terminal review submission of the app, plus the items of each reusable READY_FOR_REVIEW draft. */
async function readSubmissions(client: AscClient, appId: string): Promise<{ refs: SubmissionRef[]; drafts: OpenSubmission[] }> {
  const all = await client.getAll<JsonApiResource>("/v1/reviewSubmissions", {
    "filter[app]": appId,
    "filter[platform]": "IOS",
    "filter[state]": NON_TERMINAL_SUBMISSION_STATES.join(","),
    limit: "200",
  });
  const refs = parseSubmissions({ data: all.data });
  const drafts: OpenSubmission[] = [];
  for (const ref of refs.filter((r) => r.state === OPEN_SUBMISSION_STATE).slice(0, 5)) {
    const items = await client.getAll<JsonApiResource>(`/v1/reviewSubmissions/${seg(ref.id)}/items`, {
      include: "appStoreVersion",
      "fields[reviewSubmissionItems]": "state,appStoreVersion",
      limit: "200",
    });
    drafts.push(parseOpenSubmission(ref.id, { data: items.data }));
  }
  return { refs, drafts };
}

/** Runs the operations in order. Returns null on success, or the failure message (steps are updated either way). */
async function executeOps(client: AscClient, ops: Op[], steps: Step[], log: (line: string) => void): Promise<string | null> {
  let createdSubmissionId: string | null = null;
  for (let i = 0; i < ops.length; i++) {
    const op = ops[i]!;
    const description = describeOp(op);
    log(description);
    try {
      switch (op.kind) {
        case "createVersion":
          throw new Error("createVersion is executed before planning the remaining steps.");
        case "setWhatsNew":
          await client.patch(`/v1/appStoreVersionLocalizations/${seg(op.localizationId)}`, {
            data: { type: "appStoreVersionLocalizations", id: op.localizationId, attributes: { whatsNew: op.text } },
          });
          break;
        case "attachBuild":
          await client.patch(`/v1/appStoreVersions/${seg(op.versionId)}/relationships/build`, {
            data: { type: "builds", id: op.buildId },
          });
          break;
        case "setReleaseType":
          await client.patch(`/v1/appStoreVersions/${seg(op.versionId)}`, {
            data: { type: "appStoreVersions", id: op.versionId, attributes: { releaseType: op.releaseType } },
          });
          break;
        case "deletePhasedRelease":
          await client.delete(`/v1/appStoreVersionPhasedReleases/${seg(op.phasedReleaseId)}`);
          break;
        case "createReviewSubmission": {
          const doc = await client.post<JsonApiDoc<JsonApiResource>>("/v1/reviewSubmissions", {
            data: {
              type: "reviewSubmissions",
              attributes: { platform: "IOS" },
              relationships: { app: { data: { type: "apps", id: op.appId } } },
            },
          });
          createdSubmissionId = doc.data.id;
          break;
        }
        case "addSubmissionItem": {
          const submissionId = op.submissionId ?? createdSubmissionId;
          if (submissionId === null) throw new Error("No review submission to add the version to.");
          await client.post("/v1/reviewSubmissionItems", {
            data: {
              type: "reviewSubmissionItems",
              relationships: {
                reviewSubmission: { data: { type: "reviewSubmissions", id: submissionId } },
                appStoreVersion: { data: { type: "appStoreVersions", id: op.versionId } },
              },
            },
          });
          break;
        }
        case "submitReviewSubmission": {
          const submissionId = op.submissionId ?? createdSubmissionId;
          if (submissionId === null) throw new Error("No review submission to submit.");
          await client.patch(`/v1/reviewSubmissions/${seg(submissionId)}`, {
            data: { type: "reviewSubmissions", id: submissionId, attributes: { submitted: true } },
          });
          break;
        }
      }
      steps.push({ description, status: "done" });
    } catch (e) {
      steps.push({ description, status: "failed" });
      for (const rest of ops.slice(i + 1)) steps.push({ description: describeOp(rest), status: "skipped" });
      return `${(e as Error).message} (while trying to: ${description}).`;
    }
  }
  return null;
}
