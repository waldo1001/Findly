import { describe, expect, it } from "vitest";
import { AscClient } from "../src/http";
import { runRelease, type ReleaseResult } from "../src/release";
import {
  APP_ID,
  API,
  buildLinkageDoc,
  buildRefDoc,
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
const e = encodeURIComponent;

interface World {
  /** Newest VALID build; `null` => none. */
  build?: { id: string; buildNumber: string; marketingVersion?: string } | null;
  /** ALL iOS versions of the app. */
  versions?: VersionFx[];
  locs?: LocalizationFx[];
  attachedBuildId?: string | null;
  review?: ReviewDetailFx | null;
  phasedId?: string | null;
  /** Non-terminal review submissions; READY_FOR_REVIEW ones may carry items. */
  submissions?: Array<{ id: string; state: string; items?: ItemFx[] }>;
  /** Version returned by POST /v1/appStoreVersions. */
  created?: VersionFx;
  /** Version state returned by the final GET /v1/appStoreVersions/{id}. */
  afterState?: string;
  /** The build attached to an in-flight version (GET /v1/appStoreVersions/{id}/build). */
  attached?: { id: string; buildNumber: string } | null;
  /** App Review details of the previous live version (the proxy read before a new version is created). */
  proxyReview?: ReviewDetailFx | null;
}

function routesFor(w: World): Route[] {
  const build = w.build === undefined ? { id: "b240", buildNumber: "240", marketingVersion: "1.2.0" } : w.build;
  const versions = w.versions ?? [];
  const created = w.created ?? { id: "vNEW", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "AFTER_APPROVAL" };
  const mv = build?.marketingVersion ?? "1.2.0";
  const target = versions.find((v) => v.versionString === mv) ?? created;
  const vid = e(target.id);
  const attached = w.attached === undefined ? { id: "b240", buildNumber: "240" } : w.attached;
  const submissions = w.submissions ?? [];
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
    on("GET", "/v1/reviewSubmissions", { body: submissionsDoc(submissions.map((s) => ({ id: s.id, state: s.state }))) }),
    on("PATCH", "/v1/appStoreVersionLocalizations/l-gb", { body: { data: { id: "l-gb" } } }),
    on("PATCH", "/v1/appStoreVersionLocalizations/l-nl", { body: { data: { id: "l-nl" } } }),
    on("PATCH", `/v1/appStoreVersions/${vid}/relationships/build`, { status: 204 }),
    on("PATCH", `/v1/appStoreVersions/${vid}`, { body: { data: { id: target.id } } }),
    on("DELETE", "/v1/appStoreVersionPhasedReleases/ph1", { status: 204 }),
    on("POST", "/v1/reviewSubmissions", { status: 201, body: { data: { type: "reviewSubmissions", id: "rsNEW" } } }),
    on("POST", "/v1/reviewSubmissionItems", { status: 201, body: { data: { type: "reviewSubmissionItems", id: "iNEW" } } }),
    on("PATCH", "/v1/reviewSubmissions/rsNEW", { body: { data: { id: "rsNEW" } } }),
    on("GET", `/v1/appStoreVersions/${vid}`, { body: singleVersionDoc({ ...target, state: w.afterState ?? "WAITING_FOR_REVIEW" }) }),
  ];
  for (const v of versions) {
    // Every listed version can be asked for its attached build; the others also for their App Review details (the proxy).
    routes.push(
      on("GET", `/v1/appStoreVersions/${e(v.id)}/build`, {
        body: buildRefDoc(attached === null ? null : attached.id, attached?.buildNumber),
      }),
    );
    if (e(v.id) !== vid) {
      routes.push(
        on("GET", `/v1/appStoreVersions/${e(v.id)}/appStoreReviewDetail`, () =>
          w.proxyReview === null ? { status: 404, body: errorDoc(404, "NOT_FOUND", "none") } : { body: reviewDetailDoc(w.proxyReview ?? GOOD_REVIEW) },
        ),
      );
    }
  }
  for (const s of submissions) {
    if (s.state === "READY_FOR_REVIEW") {
      routes.push(on("GET", `/v1/reviewSubmissions/${s.id}/items`, { body: submissionItemsDoc(s.items ?? []) }));
    }
    routes.push(on("PATCH", `/v1/reviewSubmissions/${s.id}`, { body: { data: { id: s.id } } }));
  }
  return routes;
}

async function run(w: World, dryRun: boolean, extra: Route[] = [], notes = NOTES) {
  const stub = createStubFetch([...extra, ...routesFor(w)]);
  const client = new AscClient({ token: () => "t", dryRun, fetch: stub.fetch });
  const logs: string[] = [];
  const result: ReleaseResult = await runRelease(client, { appId: APP_ID, notes }, (l) => logs.push(l));
  return { stub, result, logs };
}

const EDITABLE: VersionFx = { id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "MANUAL" };
const LIVE_110: VersionFx = { id: "v110", versionString: "1.1.0", state: "READY_FOR_SALE", createdDate: "2026-09-01T00:00:00Z" };
const mutations = (stub: ReturnType<typeof createStubFetch>) => stub.sequence().filter((s) => !s.startsWith("GET "));

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

  it("queries the newest eligible VALID iOS build, ALL iOS versions, every non-terminal submission, and only the review-detail fields it needs", async () => {
    const { stub } = await run({ versions: [EDITABLE] }, false);
    const q = (path: string) => stub.calls.find((c) => new URL(c.url).pathname === path)!.query;
    expect(q("/v1/builds")).toMatchObject({
      "filter[app]": APP_ID,
      "filter[processingState]": "VALID",
      "filter[buildAudienceType]": "APP_STORE_ELIGIBLE",
      "filter[preReleaseVersion.platform]": "IOS",
      "filter[expired]": "false",
      sort: "-uploadedDate",
      include: "preReleaseVersion",
      limit: "1",
    });
    const versions = q(`/v1/apps/${APP_ID}/appStoreVersions`);
    expect(versions).toMatchObject({ "filter[platform]": "IOS", limit: "200" });
    expect(versions["filter[versionString]"]).toBeUndefined();
    const detail = q("/v1/appStoreVersions/v120/appStoreReviewDetail");
    expect(detail["fields[appStoreReviewDetails]"]).toBe("demoAccountRequired,demoAccountName");
    const subs = q("/v1/reviewSubmissions");
    expect(subs).toMatchObject({ "filter[app]": APP_ID, "filter[platform]": "IOS" });
    expect(subs["filter[state]"]!.split(",").sort()).toEqual(
      ["CANCELING", "COMPLETING", "IN_REVIEW", "READY_FOR_REVIEW", "UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW"],
    );
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
    expect(mutations(stub)).toEqual(["POST /v1/reviewSubmissions", "POST /v1/reviewSubmissionItems", "PATCH /v1/reviewSubmissions/rsNEW"]);
    expect(result.outcome).toBe("submitted");
  });

  it("reuses an open review submission instead of creating one", async () => {
    const { stub } = await run({ versions: [EDITABLE], submissions: [{ id: "rsOPEN", state: "READY_FOR_REVIEW", items: [] }] }, false);
    expect(stub.sequence()).toContain("GET /v1/reviewSubmissions/rsOPEN/items");
    expect(stub.sequence()).not.toContain("POST /v1/reviewSubmissions");
    const post = stub.calls.find((c) => c.method === "POST" && new URL(c.url).pathname === "/v1/reviewSubmissionItems")!;
    expect(post.body).toMatchObject({ data: { relationships: { reviewSubmission: { data: { id: "rsOPEN" } } } } });
    expect(stub.sequence()).toContain("PATCH /v1/reviewSubmissions/rsOPEN");
  });

  it("percent-encodes ids in paths, so a hostile id cannot alter the path", async () => {
    const { stub } = await run({ versions: [{ ...EDITABLE, id: "v1/../x" }] }, false);
    const paths = stub.calls.map((c) => new URL(c.url).pathname);
    expect(paths.some((p) => p.includes("/../"))).toBe(false);
    expect(paths).toContain("/v1/appStoreVersions/v1%2F..%2Fx/appStoreVersionLocalizations");
  });
});

describe("new version (live run)", () => {
  it("checks submissions and the previous live version's review details BEFORE creating, then proceeds from the created version's real state", async () => {
    const { stub, result } = await run({ versions: [LIVE_110] }, false);
    expect(stub.sequence()).toEqual([
      "GET /v1/builds",
      `GET /v1/apps/${APP_ID}/appStoreVersions`,
      "GET /v1/reviewSubmissions",
      "GET /v1/appStoreVersions/v110/appStoreReviewDetail",
      "POST /v1/appStoreVersions",
      "GET /v1/appStoreVersions/vNEW/appStoreVersionLocalizations",
      "GET /v1/appStoreVersions/vNEW/relationships/build",
      "GET /v1/appStoreVersions/vNEW/appStoreReviewDetail",
      "GET /v1/appStoreVersions/vNEW/relationships/appStoreVersionPhasedRelease",
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
    expect(result.steps[0]!.description).toContain("Create App Store version 1.2.0");
    expect(result.steps[0]!.status).toBe("done");
  });

  it("a first release (no versions at all) has no previous live version to read as a proxy", async () => {
    const { stub, result } = await run({ versions: [] }, false);
    expect(stub.sequence().slice(0, 4)).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`, "GET /v1/reviewSubmissions", "POST /v1/appStoreVersions"]);
    expect(result.outcome).toBe("submitted");
  });

  it("an unresolved-issues submission fails BEFORE the version is created", async () => {
    const { stub, result } = await run({ versions: [LIVE_110], submissions: [{ id: "rsX", state: "UNRESOLVED_ISSUES" }] }, false);
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("UNRESOLVED_ISSUES");
    expect(result.message).toContain("resolve or resubmit it in App Store Connect");
    expect(mutations(stub)).toEqual([]);
  });

  it("a previous live version without a demo account fails BEFORE the version is created", async () => {
    const { stub, result } = await run({ versions: [LIVE_110], proxyReview: { demoAccountRequired: false } }, false);
    expect(result.outcome).toBe("failed");
    expect(result.message).toMatch(/demo account/i);
    expect(result.message).toContain("1.1.0");
    expect(mutations(stub)).toEqual([]);
  });

  it("a previous live version with no review details at all (404) also fails before creating", async () => {
    const { stub, result } = await run({ versions: [LIVE_110], proxyReview: null }, false);
    expect(result.outcome).toBe("failed");
    expect(mutations(stub)).toEqual([]);
  });

  it("after creating, the new version's own missing demo account is authoritative: fails and says the draft exists, keeping the created step", async () => {
    const { result, stub } = await run({ versions: [LIVE_110], review: { demoAccountRequired: false } }, false);
    expect(result.outcome).toBe("failed");
    expect(result.message).toMatch(/demo account/i);
    expect(result.message).toMatch(/draft version 1\.2\.0 was created/i);
    expect(result.steps).toEqual([{ description: expect.stringContaining("Create App Store version 1.2.0"), status: "done" }]);
    expect(stub.sequence().filter((s) => s.startsWith("PATCH"))).toEqual([]);
  });

  it("a read failure after creating keeps the draft note and the completed steps in the result", async () => {
    const { result } = await run(
      { versions: [LIVE_110] },
      false,
      [on("GET", "/v1/appStoreVersions/vNEW/appStoreVersionLocalizations", { status: 500, body: errorDoc(500, "UNEXPECTED_ERROR", "Apple had a bad day.") })],
    );
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("Apple had a bad day.");
    expect(result.message).toMatch(/draft version 1\.2\.0 was created/i);
    expect(result.steps.map((s) => s.status)).toEqual(["done"]);
    expect(result.version).toBe("1.2.0");
    expect(result.buildNumber).toBe("240");
  });

  it("a failure in a later step after creating keeps the draft step and says so", async () => {
    const { result } = await run(
      { versions: [LIVE_110] },
      false,
      [on("PATCH", "/v1/appStoreVersions/vNEW/relationships/build", { status: 409, body: errorDoc(409, "X", "Missing export compliance.") })],
    );
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("Missing export compliance.");
    expect(result.message).toMatch(/draft version 1\.2\.0 was created/i);
    expect(result.steps[0]).toMatchObject({ status: "done" });
    expect(result.steps.map((s) => s.status)).toContain("failed");
  });
});

describe("already in review (today: 1.2.0 build 240 is WAITING_FOR_REVIEW)", () => {
  for (const dryRun of [true, false]) {
    it(`reports the state and stops with three GETs and nothing else (dry_run=${dryRun})`, async () => {
      const { stub, result } = await run({ versions: [{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }] }, dryRun);
      expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`, "GET /v1/appStoreVersions/v120/build"]);
      expect(result.outcome).toBe("stopped");
      expect(result.stateBefore).toBe("WAITING_FOR_REVIEW");
      expect(result.version).toBe("1.2.0");
      expect(result.buildNumber).toBe("240");
      expect(result.message).toContain("WAITING_FOR_REVIEW");
      expect(result.steps).toEqual([]);
    });
  }

  it("names the build actually attached, and says the newest one is not in review when they differ", async () => {
    const { result } = await run(
      { versions: [{ id: "v120", versionString: "1.2.0", state: "IN_REVIEW" }], attached: { id: "b239", buildNumber: "239" } },
      true,
    );
    expect(result.outcome).toBe("stopped");
    expect(result.buildNumber).toBe("239");
    expect(result.message).toMatch(/not the one in review/i);
    expect(result.message).toContain("240");
  });

  it("still stops, honestly, when the attached build cannot be read", async () => {
    const { result } = await run({ versions: [{ id: "v120", versionString: "1.2.0", state: "IN_REVIEW" }], attached: null }, true);
    expect(result.outcome).toBe("stopped");
    expect(result.buildNumber).toBeNull();
    expect(result.message).toMatch(/could not be determined/i);
  });
});

describe("another version is in the way (Apple allows one non-live version at a time)", () => {
  it("1.2.1 build while 1.2.0 waits for review: stopped (exit-0 outcome), naming 1.2.0, after two GETs and the build read", async () => {
    const { stub, result } = await run(
      {
        build: { id: "b241", buildNumber: "241", marketingVersion: "1.2.1" },
        versions: [{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }],
      },
      false,
    );
    expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`, "GET /v1/appStoreVersions/v120/build"]);
    expect(result.outcome).toBe("stopped");
    expect(result.version).toBe("1.2.0");
    expect(result.buildNumber).toBe("240");
    expect(result.message).toContain("1.2.0");
    expect(result.message).toContain("1.2.1");
  });

  it("an editable 1.2.0 draft + a 1.2.1 build: fails naming 1.2.0, after two GETs, dry run or not", async () => {
    for (const dryRun of [true, false]) {
      const { stub, result } = await run(
        {
          build: { id: "b241", buildNumber: "241", marketingVersion: "1.2.1" },
          versions: [{ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" }],
        },
        dryRun,
      );
      expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`]);
      expect(result.outcome).toBe("failed");
      expect(result.message).toContain("1.2.0");
    }
  });
});

describe("version already live", () => {
  it("fails with the bump hint, two GETs only", async () => {
    const { stub, result } = await run({ versions: [{ id: "v120", versionString: "1.2.0", state: "READY_FOR_SALE" }] }, false);
    expect(stub.sequence()).toEqual(["GET /v1/builds", `GET /v1/apps/${APP_ID}/appStoreVersions`]);
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("bump MARKETING_VERSION in mobile/ios/project.yml");
  });
});

describe("unresolved review submissions block everything, before any change", () => {
  for (const state of ["UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW", "CANCELING", "COMPLETING"]) {
    for (const dryRun of [true, false]) {
      it(`${state} fails an editable version (dry_run=${dryRun}) with only GETs sent`, async () => {
        const { stub, result } = await run({ versions: [EDITABLE], submissions: [{ id: "rsX", state }] }, dryRun);
        expect(result.outcome).toBe("failed");
        expect(result.message).toContain(state);
        expect(result.message).toContain("resolve or resubmit it in App Store Connect");
        expect(mutations(stub)).toEqual([]);
        expect(stub.calls.every((c) => c.method === "GET")).toBe(true);
      });
    }
  }

  it("an open draft that holds other items also fails, before any change", async () => {
    const { stub, result } = await run(
      { versions: [EDITABLE], submissions: [{ id: "rsD", state: "READY_FOR_REVIEW", items: [{ id: "i1" }] }] },
      false,
    );
    expect(result.outcome).toBe("failed");
    expect(result.message).toMatch(/other items/i);
    expect(mutations(stub)).toEqual([]);
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

  it("new version: GETs only, but the blockers and the proxy review details are already checked", async () => {
    const { stub, result } = await run({ versions: [LIVE_110] }, true);
    expect(stub.sequence()).toEqual([
      "GET /v1/builds",
      `GET /v1/apps/${APP_ID}/appStoreVersions`,
      "GET /v1/reviewSubmissions",
      "GET /v1/appStoreVersions/v110/appStoreReviewDetail",
    ]);
    expect(result.outcome).toBe("dry-run");
    expect(result.steps[0]!.description).toContain("Create App Store version 1.2.0");
    expect(result.steps.map((s) => s.description).join("\n")).toMatch(/after the version exists/i);
    expect(result.message).toContain("1.1.0");
  });

  it("new version: a blocking submission or a proxy without demo account fails the dry run too", async () => {
    const a = await run({ versions: [LIVE_110], submissions: [{ id: "rsX", state: "IN_REVIEW" }] }, true);
    expect(a.result.outcome).toBe("failed");
    const b = await run({ versions: [LIVE_110], proxyReview: { demoAccountRequired: false } }, true);
    expect(b.result.outcome).toBe("failed");
    expect(a.stub.calls.every((c) => c.method === "GET")).toBe(true);
    expect(b.stub.calls.every((c) => c.method === "GET")).toBe(true);
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
    expect(mutations(stub)).toEqual([]);
  });

  it("an API error on a read keeps the version, build and state that were already known", async () => {
    const { result } = await run(
      { versions: [EDITABLE] },
      false,
      [on("GET", "/v1/appStoreVersions/v120/appStoreVersionLocalizations", { status: 503, body: errorDoc(503, "SERVICE_UNAVAILABLE", "Try later.") })],
    );
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("Try later.");
    expect(result.message).toMatch(/no changes/i);
    expect(result.version).toBe("1.2.0");
    expect(result.buildNumber).toBe("240");
  });

  it("an Apple error mid-run surfaces errors[].detail, records what was done, and stops", async () => {
    const { result, stub } = await run(
      { versions: [EDITABLE] },
      false,
      [on("PATCH", "/v1/appStoreVersions/v120/relationships/build", { status: 409, body: errorDoc(409, "ENTITY_ERROR", "The build is missing export compliance information.") })],
    );
    expect(result.outcome).toBe("failed");
    expect(result.message).toContain("The build is missing export compliance information.");
    expect(result.steps.map((s) => s.status)).toEqual(["done", "done", "failed", "skipped", "skipped", "skipped", "skipped"]);
    expect(stub.sequence().at(-1)).toBe("PATCH /v1/appStoreVersions/v120/relationships/build");
  });

  it("logs plain progress lines without credentials", async () => {
    const { logs } = await run({ versions: [EDITABLE] }, false);
    expect(logs.length).toBeGreaterThan(0);
    expect(logs.join("\n")).not.toMatch(/Bearer|BEGIN/);
  });
});

it("targets the production App Store Connect origin", async () => {
  const { stub } = await run({ versions: [EDITABLE] }, true);
  expect(new URL(stub.calls[0]!.url).origin).toBe(API);
});
