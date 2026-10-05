import type { AscClient, JsonApiDoc, JsonApiResource } from "./http";
import type { AppVersion } from "./model";
import {
  parseLinkageId,
  parseLocalizations,
  parseNewestBuild,
  parseOpenSubmission,
  parseReviewDetail,
  parseSubmissionIds,
  parseVersions,
} from "./parse";
import {
  RELEASE_TYPE_AFTER_APPROVAL,
  chooseOpenSubmission,
  decide,
  describeOp,
  planCreate,
  planEdit,
  type Details,
  type Op,
} from "./planner";

/**
 * Orchestrates one release: read state -> decide -> (create the version) -> read details -> plan ->
 * execute -> read the resulting state. All store access goes through the injected {@link AscClient},
 * which refuses non-GET requests in dry-run mode.
 *
 * Endpoints (https://developer.apple.com/documentation/appstoreconnectapi/…):
 *   GET   /v1/builds                                     get-v1-builds
 *   GET   /v1/apps/{id}/appStoreVersions                 get-v1-apps-_id_-appstoreversions
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

export async function runRelease(client: AscClient, input: ReleaseInput, log: (line: string) => void): Promise<ReleaseResult> {
  const { appId, notes } = input;
  const result = (r: Partial<ReleaseResult> & Pick<ReleaseResult, "outcome" | "message">): ReleaseResult => ({
    dryRun: client.dryRun,
    version: null,
    buildNumber: null,
    stateBefore: null,
    stateAfter: null,
    steps: [],
    notes,
    ...r,
  });

  log(client.dryRun ? "DRY RUN: only GET requests will be sent." : "LIVE RUN: changes will be made in App Store Connect.");

  log("Looking up the newest processed build...");
  const build = parseNewestBuild(
    await client.get<JsonApiDoc<JsonApiResource[]>>("/v1/builds", {
      "filter[app]": appId,
      "filter[processingState]": "VALID",
      "filter[preReleaseVersion.platform]": "IOS",
      "filter[expired]": "false",
      sort: "-uploadedDate",
      include: "preReleaseVersion",
      limit: "1",
    }),
  );
  if (build) log(`Newest processed build: ${build.marketingVersion ?? "(unknown version)"} (${build.buildNumber}).`);

  let versions: AppVersion[] = [];
  if (build?.marketingVersion) {
    log(`Looking up App Store version ${build.marketingVersion} (iOS)...`);
    versions = parseVersions(
      await client.get<JsonApiDoc<JsonApiResource[]>>(`/v1/apps/${appId}/appStoreVersions`, {
        "filter[platform]": "IOS",
        "filter[versionString]": build.marketingVersion,
        limit: "20",
      }),
    );
  }

  const decision = decide({ build, versions });
  const ids = { version: build?.marketingVersion ?? null, buildNumber: build?.buildNumber ?? null };

  if (decision.kind === "fail") {
    return result({ outcome: "failed", message: decision.message, ...ids });
  }
  if (decision.kind === "stop") {
    log(decision.message);
    return result({ outcome: "stopped", message: decision.message, stateBefore: decision.version.state, ...ids });
  }

  const steps: Step[] = [];
  let version: AppVersion;
  let createdDraft = false;

  if (decision.kind === "create") {
    const createOps = planCreate({ appId, build: decision.build });
    const first = createOps[0]!;
    if (client.dryRun) {
      return result({
        outcome: "dry-run",
        message:
          `Version ${decision.build.marketingVersion} does not exist in App Store Connect yet. A live run would create it, ` +
          "then plan the remaining steps from its real state. " + NO_CHANGES,
        steps: [
          { description: describeOp(first), status: "planned" },
          {
            description:
              "After the version exists: set What's New on every localization, attach the build, verify App Review " +
              "details (sign-in required, demo account), and submit for review",
            status: "planned",
          },
        ],
        ...ids,
      });
    }
    log(describeOp(first));
    const created = await client.post<JsonApiDoc<JsonApiResource>>("/v1/appStoreVersions", {
      data: {
        type: "appStoreVersions",
        attributes: { platform: "IOS", versionString: decision.build.marketingVersion, releaseType: RELEASE_TYPE_AFTER_APPROVAL },
        relationships: { app: { data: { type: "apps", id: appId } } },
      },
    });
    createdDraft = true;
    steps.push({ description: describeOp(first), status: "done" });
    const [createdVersion] = parseVersions({ data: [created.data] });
    const again = decide({ build: decision.build, versions: createdVersion ? [createdVersion] : [] });
    if (again.kind !== "edit") {
      return result({
        outcome: "failed",
        message:
          `${again.kind === "fail" || again.kind === "stop" ? again.message : "The created version could not be read back."} ` +
          `The draft version ${decision.build.marketingVersion} was created before this check; nothing else was changed.`,
        steps,
        ...ids,
      });
    }
    version = again.version;
  } else {
    version = decision.version;
  }

  const failedBeforeChanges = (message: string): ReleaseResult =>
    result({
      outcome: "failed",
      message: createdDraft
        ? `${message} The draft version ${version.versionString} was created before this check; nothing else was changed.`
        : `${message} ${NO_CHANGES}`,
      stateBefore: version.state,
      steps,
      ...ids,
    });

  log(`Version ${version.versionString} is ${version.state}; reading its details...`);
  const details = await readDetails(client, appId, version);
  const plan = planEdit({ appId, notes, build: decision.build, version, details });
  if (plan.kind === "fail") return failedBeforeChanges(plan.message);

  if (client.dryRun) {
    const planned: Step[] = plan.ops.map((op) => ({ description: describeOp(op), status: "planned" }));
    for (const s of planned) log(`Would: ${s.description}`);
    return result({
      outcome: "dry-run",
      message: `Dry run: ${plan.ops.length} change(s) would be made to submit ${version.versionString} (build ${decision.build.buildNumber}). ${NO_CHANGES}`,
      stateBefore: version.state,
      steps: planned,
      ...ids,
    });
  }

  const failure = await executeOps(client, plan.ops, version, steps, log);
  if (failure !== null) {
    return result({ outcome: "failed", message: failure, stateBefore: version.state, steps, ...ids });
  }

  let stateAfter: string | null = null;
  try {
    const doc = await client.get<JsonApiDoc<JsonApiResource>>(`/v1/appStoreVersions/${version.id}`);
    stateAfter = parseVersions({ data: [doc.data] })[0]?.state ?? null;
  } catch {
    log("Submitted, but the version state could not be read back.");
  }
  return result({
    outcome: "submitted",
    message: `Submitted ${version.versionString} (build ${decision.build.buildNumber}) for App Review.`,
    stateBefore: version.state,
    stateAfter,
    steps,
    ...ids,
  });
}

async function readDetails(client: AscClient, appId: string, version: AppVersion): Promise<Details> {
  const base = `/v1/appStoreVersions/${version.id}`;
  const localizations = parseLocalizations(
    await client.getAll<JsonApiResource>(`${base}/appStoreVersionLocalizations`, {
      "fields[appStoreVersionLocalizations]": "locale,whatsNew",
      limit: "200",
    }),
  );
  const attachedBuildId = parseLinkageId(await client.getOptional(`${base}/relationships/build`));
  // Only what the check needs: the demo account's password is never requested, so it never enters memory.
  const reviewDetail = parseReviewDetail(
    await client.getOptional(`${base}/appStoreReviewDetail`, {
      "fields[appStoreReviewDetails]": "demoAccountRequired,demoAccountName",
    }),
  );
  const phasedReleaseId = parseLinkageId(await client.getOptional(`${base}/relationships/appStoreVersionPhasedRelease`));

  const submissions = parseSubmissionIds(
    await client.get<JsonApiDoc<JsonApiResource[]>>("/v1/reviewSubmissions", {
      "filter[app]": appId,
      "filter[platform]": "IOS",
      "filter[state]": "READY_FOR_REVIEW",
      limit: "10",
    }),
  );
  const open = [];
  for (const id of submissions.slice(0, 5)) {
    const items = await client.get<JsonApiDoc<JsonApiResource[]>>(`/v1/reviewSubmissions/${id}/items`, {
      include: "appStoreVersion",
      "fields[reviewSubmissionItems]": "state,appStoreVersion",
      limit: "200",
    });
    open.push(parseOpenSubmission(id, items));
  }
  return {
    localizations,
    attachedBuildId,
    reviewDetail,
    phasedReleaseId,
    openSubmission: chooseOpenSubmission(open, version.id),
  };
}

/** Runs the operations in order. Returns null on success, or the failure message (steps are updated either way). */
async function executeOps(
  client: AscClient,
  ops: Op[],
  version: AppVersion,
  steps: Step[],
  log: (line: string) => void,
): Promise<string | null> {
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
          await client.patch(`/v1/appStoreVersionLocalizations/${op.localizationId}`, {
            data: { type: "appStoreVersionLocalizations", id: op.localizationId, attributes: { whatsNew: op.text } },
          });
          break;
        case "attachBuild":
          await client.patch(`/v1/appStoreVersions/${op.versionId}/relationships/build`, {
            data: { type: "builds", id: op.buildId },
          });
          break;
        case "setReleaseType":
          await client.patch(`/v1/appStoreVersions/${op.versionId}`, {
            data: { type: "appStoreVersions", id: op.versionId, attributes: { releaseType: op.releaseType } },
          });
          break;
        case "deletePhasedRelease":
          await client.delete(`/v1/appStoreVersionPhasedReleases/${op.phasedReleaseId}`);
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
          await client.patch(`/v1/reviewSubmissions/${submissionId}`, {
            data: { type: "reviewSubmissions", id: submissionId, attributes: { submitted: true } },
          });
          break;
        }
      }
      steps.push({ description, status: "done" });
    } catch (e) {
      steps.push({ description, status: "failed" });
      for (const rest of ops.slice(i + 1)) steps.push({ description: describeOp(rest), status: "skipped" });
      return (
        `${(e as Error).message} (while trying to: ${description}). ` +
        `Steps already completed on version ${version.versionString} were not rolled back; re-running the workflow is safe.`
      );
    }
  }
  return null;
}

