import { describe, expect, it } from "vitest";
import { AscClient } from "../src/http";
import { runRelease, type ReleaseResult } from "../src/release";
import {
  APP_ID,
  API,
  buildLinkageDoc,
  buildsDoc,
  errorDoc,
  localizationsDoc,
  phasedLinkageDoc,
  reviewDetailDoc,
  singleVersionDoc,
  submissionItemsDoc,
  submissionsDoc,
  versionsDoc,
  type ItemFx,
  type LocalizationFx,
  type ReviewDetailFx,
  type VersionFx,
} from "./fixtures";
import { createStubFetch, on, type Route } from "./stubFetch";

const NOTES = "Faster map refresh and a fix for ghost devices.";
const GOOD_REVIEW: ReviewDetailFx = { demoAccountRequired: true, demoAccountName: "review@example.test" };

interface World {
  /** Newest VALID build; `null` => none. */
  build?: { id: string; buildNumber: string; marketingVersion?: string } | null;
  versions?: VersionFx[];
  locs?: LocalizationFx[];
  attachedBuildId?: string | null;
  review?: ReviewDetailFx | null;
  phasedId?: string | null;
  /** READY_FOR_REVIEW submissions, each with its items. */
  openSubmissions?: Array<{ id: string; items: ItemFx[] }>;
  /** Version returned by POST /v1/appStoreVersions. */
  created?: VersionFx;
  /** Version state returned by the final GET /v1/appStoreVersions/{id}. */
  afterState?: string;
}

function routesFor(w: World): Route[] {
  const build = w.build === undefined ? { id: "b240", buildNumber: "240", marketingVersion: "1.2.0" } : w.build;
  const versions = w.versions ?? [];
  const created = w.created ?? { id: "vNEW", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "AFTER_APPROVAL" };
  const target = versions[0] ?? created;
  const vid = target.id;
  const routes: Route[] = [
    on("GET", "/v1/builds", { body: buildsDoc(build === null ? [] : [build]) }),
    on("GET", `/v1/apps/${APP_ID}/appStoreVersions`, { body: versionsDoc(versions) }),
    on("POST", "/v1/appStoreVersions", { status: 201, body: singleVersionDoc(created) }),
    on("GET", `/v1/appStoreVersions/${vid}/appStoreVersionLocalizations`, {
      body: localizationsDoc(w.locs ?? [{ id: "l-gb", locale: "en-GB", whatsNew: "old" }, { id: "l-nl", locale: "nl-NL" }]),
    }),
    on("GET", `/v1/appStoreVersions/${vid}/relationships/build`, { body: buildLinkageDoc(w.attachedBuildId ?? null) }),
    on("GET", `/v1/appStoreVersions/${vid}/appStoreReviewDetail`, () =>
      w.review === null ? { status: 404, body: errorDoc(404, "NOT_FOUND", "no review detail") } : { body: reviewDetailDoc(w.review ?? GOOD_REVIEW) },
    ),
    on("GET", `/v1/appStoreVersions/${vid}/relationships/appStoreVersionPhasedRelease`, { body: phasedLinkageDoc(w.phasedId ?? null) }),
    on("GET", "/v1/reviewSubmissions", { body: submissionsDoc((w.openSubmissions ?? []).map((s) => ({ id: s.id, state: "READY_FOR_REVIEW" }))) }),
    on("PATCH", "/v1/appStoreVersionLocalizations/l-gb", { body: { data: { id: "l-gb" } } }),
    on("PATCH", "/v1/appStoreVersionLocalizations/l-nl", { body: { data: { id: "l-nl" } } }),
    on("PATCH", `/v1/appStoreVersions/${vid}/relationships/build`, { status: 204 }),
    on("PATCH", `/v1/appStoreVersions/${vid}`, { body: { data: { id: vid } } }),
    on("DELETE", "/v1/appStoreVersionPhasedReleases/ph1", { status: 204 }),
    on("POST", "/v1/reviewSubmissions", { status: 201, body: { data: { type: "reviewSubmissions", id: "rsNEW" } } }),
    on("POST", "/v1/reviewSubmissionItems", { status: 201, body: { data: { type: "reviewSubmissionItems", id: "iNEW" } } }),
    on("PATCH", "/v1/reviewSubmissions/rsNEW", { body: { data: { id: "rsNEW" } } }),
    on("GET", `/v1/appStoreVersions/${vid}`, { body: singleVersionDoc({ ...target, state: w.afterState ?? "WAITING_FOR_REVIEW" }) }),
  ];
  for (const s of w.openSubmissions ?? []) {
    routes.push(on("GET", `/v1/reviewSubmissions/${s.id}/items`, { body: submissionItemsDoc(s.items) }));
    routes.push(on("PATCH", `/v1/reviewSubmissions/${s.id}`, { body: { data: { id: s.id } } }));
    routes.push(on("POST", "/v1/reviewSubmissionItems", { status: 201, body: { data: { id: "iX" } } }));
  }
  return routes;
}

async function run(w: World, dryRun: boolean, notes = NOTES) {
  const stub = createStubFetch(routesFor(w));
  const client = new AscClient({ token: () => "t", dryRun, fetch: stub.fetch });
  const logs: string[] = [];
  const result: ReleaseResult = await runRelease(client, { appId: APP_ID, notes }, (l) => logs.push(l));
  return { stub, result, logs };
}

const EDITABLE: VersionFx = { id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "MANUAL" };

describe("existing editable version (live run)", () => {
  it("calls exactly: look-up GETs, then the mutations in contract order, then a final state read", async () => {
    const { stub, result } = await run({ versions: [EDITABLE], phasedId: "ph1" }, false);
    expect(stub.sequence()).toEqual([
      "GET /v1/builds",
      `GET /v1/apps/${APP_ID}/appStoreVersions`,
      "GET /v1/appStoreVersions/v120/appStoreVersionLocalizations",
      "GET /v1/appStoreVersions/v120/relationships/build",
      "GET /v1/appStoreVersions/v120/appStoreReviewDetail",
      "GET /v1/appStoreVersions/v120/relationships/appStoreVersionPhasedRelease",
      "GET /v1/reviewSubmissions",
      "PATCH /v1/appStoreVersionLocalizations/l-gb",
      "PATCH /v1/appStoreVersionLocalizations/l-nl",
      "PATCH /v1/appStoreVersions/v120/relationships/build",
      "PATCH /v1/appStoreVersions/v120",
      "DELETE /v1/appStoreVersionPhasedReleases/ph1",
      "POST /v1/reviewSubmissions",
      "POST /v1/reviewSubmissionItems",
      "PATCH /v1/reviewSubmissions/rsNEW",
      "GET /v1/appStoreVersions/v120",
    ]);
    expect(result.outcome).toBe("submitted");
    expect(result.version).toBe("1.2.0");
    expect(result.buildNumber).toBe("240");
    expect(result.stateAfter).toBe("WAITING_FOR_REVIEW");
    expect(result.steps.every((s) => s.status === "done")).toBe(true);
  });

  it("sends the documented request bodies", async () => {
    const { stub } = await run({ versions: [EDITABLE], phasedId: "ph1" }, false);
    const body = (method: string, path: string) =>
      stub.calls.find((c) => c.method === method && new URL(c.url).pathname === path)?.body;
    expect(body("PATCH", "/v1/appStoreVersionLocalizations/l-gb")).toEqual({
      data: { type: "appStoreVersionLocalizations", id: "l-gb", attributes: { whatsNew: NOTES } },
    });
    expect(body("PATCH", "/v1/appStoreVersions/v120/relationships/build")).toEqual({ data: { type: "builds", id: "b240" } });
    expect(body("PATCH", "/v1/appStoreVersions/v120")).toEqual({
      data: { type: "appStoreVersions", id: "v120", attributes: { releaseType: "AFTER_APPROVAL" } },
    });
    expect(body("POST", "/v1/reviewSubmissions")).toEqual({
      data: {
        type: "reviewSubmissions",
        attributes: { platform: "IOS" },
        relationships: { app: { data: { type: "apps", id: APP_ID } } },
      },
    });
    expect(body("POST", "/v1/reviewSubmissionItems")).toEqual({
      data: {
        type: "reviewSubmissionItems",
        relationships: {
          reviewSubmission: { data: { type: "reviewSubmissions", id: "rsNEW" } },
          appStoreVersion: { data: { type: "appStoreVersions", id: "v120" } },
        },
      },
    });
    expect(body("PATCH", "/v1/reviewSubmissions/rsNEW")).toEqual({
      data: { type: "reviewSubmissions", id: "rsNEW", attributes: { submitted: true } },
    });
  });

  it("queries the newest VALID iOS build and only the review-detail fields it needs (never the demo password)", async () => {
    const { stub } = await run({ versions: [EDITABLE] }, false);
    const builds = stub.calls.find((c) => new URL(c.url).pathname === "/v1/builds")!;
    expect(builds.query).toMatchObject({
      "filter[app]": APP_ID,
      "filter[processingState]": "VALID",
      "filter[preReleaseVersion.platform]": "IOS",
      "filter[expired]": "false",
      sort: "-uploadedDate",
      include: "preReleaseVersion",
      limit: "1",
    });
    const versions = stub.calls.find((c) => new URL(c.url).pathname === `/v1/apps/${APP_ID}/appStoreVersions`)!;
    expect(versions.query).toMatchObject({ "filter[platform]": "IOS", "filter[versionString]": "1.2.0" });
    const detail = stub.calls.find((c) => new URL(c.url).pathname.endsWith("/appStoreReviewDetail"))!;
    expect(detail.query["fields[appStoreReviewDetails]"]).toBe("demoAccountRequired,demoAccountName");
    expect(detail.query["fields[appStoreReviewDetails]"]).not.toContain("Password");
    const subs = stub.calls.find((c) => new URL(c.url).pathname === "/v1/reviewSubmissions")!;
    expect(subs.query).toMatchObject({ "filter[app]": APP_ID, "filter[platform]": "IOS", "filter[state]": "READY_FOR_REVIEW" });
  });

  it("skips mutations that are already satisfied (idempotent re-run)", async () => {
    const { stub, result } = await run(
      {
        versions: [{ ...EDITABLE, releaseType: "AFTER_APPROVAL" }],
        locs: [{ id: "l-gb", locale: "en-GB", whatsNew: NOTES }],
        attachedBuildId: "b240",
      },
      false,
    );
    const mutations = stub.sequence().filter((s) => !s.startsWith("GET "));
    expect(mutations).toEqual(["POST /v1/reviewSubmissions", "POST /v1/reviewSubmissionItems", "PATCH /v1/reviewSubmissions/rsNEW"]);
    expect(result.outcome).toBe("submitted");
  });

  it("reuses an open review submission instead of creating one", async () => {
    const { stub } = await run({ versions: [EDITABLE], openSubmissions: [{ id: "rsOPEN", items: [] }] }, false);
    expect(stub.sequence()).toContain("GET /v1/reviewSubmissions/rsOPEN/items");
    expect(stub.sequence()).not.toContain("POST /v1/reviewSubmissions");
    const post = stub.calls.find((c) => c.method === "POST" && new URL(c.url).pathname === "/v1/reviewSubmissionItems")!;
    expect(post.body).toMatchObject({ data: { relationships: { reviewSubmission: { data: { id: "rsOPEN" } } } } });
    expect(stub.sequence()).toContain("PATCH /v1/reviewSubmissions/rsOPEN");
  });
});

describe("new version (live run)", () => {
  it("creates the version first, then proceeds from the created version's real state", async () => {
    const { stub, result } = await run({ versions: [] }, false);
    const seq = stub.sequence();
    expect(seq.slice(0, 3)).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`, "POST /v1/appStoreVersions"]);
    expect(seq.slice(3)).toEqual([
      "GET /v1/appStoreVersions/vNEW/appStoreVersionLocalizations",
      "GET /v1/appStoreVersions/vNEW/relationships/build",
      "GET /v1/appStoreVersions/vNEW/appStoreReviewDetail",
      "GET /v1/appStoreVersions/vNEW/relationships/appStoreVersionPhasedRelease",
      "GET /v1/reviewSubmissions",
      "PATCH /v1/appStoreVersionLocalizations/l-gb",
      "PATCH /v1/appStoreVersionLocalizations/l-nl",
      "PATCH /v1/appStoreVersions/vNEW/relationships/build",
      "POST /v1/reviewSubmissions",
      "POST /v1/reviewSubmissionItems",
      "PATCH /v1/reviewSubmissions/rsNEW",
      "GET /v1/appStoreVersions/vNEW",
    ]);
    expect(stub.calls.find((c) => c.method === "POST" && new URL(c.url).pathname === "/v1/appStoreVersions")!.body).toEqual({
      data: {
        type: "appStoreVersions",
        attributes: { platform: "IOS", versionString: "1.2.0", releaseType: "AFTER_APPROVAL" },
        relationships: { app: { data: { type: "apps", id: APP_ID } } },
      },
    });
    expect(result.outcome).toBe("submitted");
  });

  it("after creating, a missing demo account fails and says the draft version now exists", async () => {
    const { result, stub } = await run({ versions: [], review: { demoAccountRequired: false } }, false);
    expect(result.outcome).toBe("failed");
    expect(result.message).toMatch(/demo account/i);
    expect(result.message).toMatch(/draft version 1\.2\.0 was created/i);
    expect(stub.sequence().filter((s) => s.startsWith("PATCH"))).toEqual([]);
  });
});

describe("already in review (today: 1.2.0 build 240 is WAITING_FOR_REVIEW)", () => {
  for (const dryRun of [true, false]) {
    it(`reports the state and stops with two GETs and nothing else (dry_run=${dryRun})`, async () => {
      const { stub, result } = await run({ versions: [{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }] }, dryRun);
      expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`]);
      expect(result.outcome).toBe("stopped");
      expect(result.stateBefore).toBe("WAITING_FOR_REVIEW");
      expect(result.version).toBe("1.2.0");
      expect(result.buildNumber).toBe("240");
      expect(result.message).toContain("WAITING_FOR_REVIEW");
      expect(result.steps).toEqual([]);
    });
  }
});

describe("version already live", () => {
  it("fails with the bump hint, two GETs only", async () => {
    const { stub, result } = await run({ versions: [{ id: "v120", versionString: "1.2.0", state: "READY_FOR_SALE" }] }, false);
    expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`]);
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("bump MARKETING_VERSION in mobile/ios/project.yml");
  });
});

describe("DRY_RUN", () => {
  it("existing editable version: GET requests only, with the exact plan reported", async () => {
    const { stub, result } = await run({ versions: [EDITABLE], phasedId: "ph1" }, true);
    expect(stub.calls.every((c) => c.method === "GET")).toBe(true);
    expect(stub.sequence()).toEqual([
      "GET /v1/builds",
      `GET /v1/apps/${APP_ID}/appStoreVersions`,
      "GET /v1/appStoreVersions/v120/appStoreVersionLocalizations",
      "GET /v1/appStoreVersions/v120/relationships/build",
      "GET /v1/appStoreVersions/v120/appStoreReviewDetail",
      "GET /v1/appStoreVersions/v120/relationships/appStoreVersionPhasedRelease",
      "GET /v1/reviewSubmissions",
    ]);
    expect(result.outcome).toBe("dry-run");
    expect(result.stateAfter).toBeNull();
    expect(result.steps.map((s) => s.status)).toEqual(new Array(result.steps.length).fill("planned"));
    expect(result.steps.map((s) => s.description)).toEqual(
      expect.arrayContaining([
        expect.stringContaining("What's New (en-GB"),
        expect.stringContaining("Attach build 240"),
        expect.stringContaining("AFTER_APPROVAL"),
        expect.stringContaining("phased release"),
        expect.stringContaining("Submit"),
      ]),
    );
  });

  it("new version: GETs only; plans the creation and says the rest follows from the created version", async () => {
    const { stub, result } = await run({ versions: [] }, true);
    expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`]);
    expect(result.outcome).toBe("dry-run");
    expect(result.steps[0]!.description).toContain("Create App Store version 1.2.0");
    expect(result.steps.map((s) => s.description).join("\n")).toMatch(/after the version exists/i);
  });

  it("a missing demo account is still caught in a dry run (existing version)", async () => {
    const { result, stub } = await run({ versions: [EDITABLE], review: null }, true);
    expect(result.outcome).toBe("failed");
    expect(stub.calls.every((c) => c.method === "GET")).toBe(true);
  });
});

describe("failures", () => {
  it("no VALID build: fails after one GET", async () => {
    const { stub, result } = await run({ build: null }, false);
    expect(stub.sequence()).toEqual(["GET /v1/builds"]);
    expect(result.outcome).toBe("failed");
    expect(result.message).toMatch(/no processed build/i);
  });

  it("missing review detail (404) fails before any change and says nothing was changed", async () => {
    const { stub, result } = await run({ versions: [EDITABLE], review: null }, false);
    expect(result.outcome).toBe("failed");
    expect(result.message).toMatch(/App Review/i);
    expect(result.message).toMatch(/no changes/i);
    expect(stub.sequence().some((s) => !s.startsWith("GET "))).toBe(false);
  });

  it("an Apple error mid-run surfaces errors[].detail, records what was done, and stops", async () => {
    const world = routesFor({ versions: [EDITABLE] });
    const stub = createStubFetch([
      on("PATCH", "/v1/appStoreVersions/v120/relationships/build", {
        status: 409,
        body: errorDoc(409, "ENTITY_ERROR", "The build is missing export compliance information."),
      }),
      ...world,
    ]);
    const client = new AscClient({ token: () => "t", dryRun: false, fetch: stub.fetch });
    const result = await runRelease(client, { appId: APP_ID, notes: NOTES }, () => {});
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("The build is missing export compliance information.");
    expect(result.steps.map((s) => s.status)).toEqual(["done", "done", "failed", "skipped", "skipped", "skipped", "skipped"]);
    expect(stub.sequence().at(-1)).toBe("PATCH /v1/appStoreVersions/v120/relationships/build");
  });

  it("logs plain progress lines without ids of secrets", async () => {
    const { logs } = await run({ versions: [EDITABLE] }, false);
    expect(logs.length).toBeGreaterThan(0);
    expect(logs.join("\n")).not.toMatch(/Bearer|BEGIN/);
  });
});

// keep the API constant referenced so a future rename of the base URL fails here too
it("targets the production App Store Connect origin", async () => {
  const { stub } = await run({ versions: [EDITABLE] }, true);
  expect(new URL(stub.calls[0]!.url).origin).toBe(API);
});
