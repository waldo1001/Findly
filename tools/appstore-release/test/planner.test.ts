import { describe, expect, it } from "vitest";
import { parseLocalizations, parseNewestBuild, parseReviewDetail, parseVersions } from "../src/parse";
import {
  chooseOpenSubmission,
  decide,
  describeOp,
  describeStop,
  planCreate,
  planEdit,
  type Decision,
  type Details,
  type Op,
} from "../src/planner";
import type { AppVersion, Build, OpenSubmission, SubmissionRef } from "../src/model";
import {
  APP_ID,
  buildsDoc,
  localizationsDoc,
  reviewDetailDoc,
  versionsDoc,
  type LocalizationFx,
  type ReviewDetailFx,
  type VersionFx,
} from "./fixtures";

const NOTES = "Faster map refresh and a fix for ghost devices.";

// Fixtures go through the real parsers, so these tests also pin the API shapes the planner depends on.
const build240 = parseNewestBuild(buildsDoc([{ id: "b240", buildNumber: "240", marketingVersion: "1.2.0" }]))!;
const build241 = parseNewestBuild(buildsDoc([{ id: "b241", buildNumber: "241", marketingVersion: "1.2.1" }]))!;

function versionsFor(...vs: VersionFx[]): AppVersion[] {
  return parseVersions(versionsDoc(vs));
}

function decideFor(vs: VersionFx[], build: Build | null = build240): Decision {
  return decide({ build, versions: versionsFor(...vs) });
}

describe("decide: which state is the release in?", () => {
  it("fails when there is no processed (VALID) build", () => {
    const d = decide({ build: parseNewestBuild(buildsDoc([])), versions: [] });
    expect(d.kind).toBe("fail");
    expect(d.kind === "fail" && d.message).toMatch(/no processed build/i);
    expect(d.kind === "fail" && d.message).toContain("VALID");
  });

  it("fails when the build's marketing version is unknown", () => {
    const b = parseNewestBuild(buildsDoc([{ id: "b1", buildNumber: "9" }]))!;
    const d = decide({ build: b, versions: [] });
    expect(d.kind).toBe("fail");
    expect(d.kind === "fail" && d.message).toMatch(/marketing version/i);
  });

  it("creates the version when App Store Connect has none for that marketing version", () => {
    const d = decideFor([{ id: "v110", versionString: "1.1.0", state: "READY_FOR_SALE" }]);
    expect(d.kind).toBe("create");
    expect(d.kind === "create" && d.build).toEqual(build240);
  });

  it("creates when the list is empty (first release): no previous live version", () => {
    expect(decideFor([])).toEqual({ kind: "create", build: build240, previousLive: null });
  });

  it("STOPs, changing nothing, when 1.2.0 is waiting for review (today's real state)", () => {
    const d = decideFor([{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }]);
    expect(d.kind).toBe("stop");
    if (d.kind !== "stop") return;
    expect(d.scope).toBe("target");
    expect(d.version.id).toBe("v120");
    expect(d.build).toEqual(build240);
  });

  it.each(["WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "ACCEPTED", "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE"])(
    "STOPs in %s",
    (state) => {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }]);
      expect(d.kind).toBe("stop");
      expect(d.kind === "stop" && d.version.state).toBe(state);
    },
  );

  it("STOP reads the deprecated appStoreState when appVersionState is absent", () => {
    const d = decideFor([{ id: "v120", versionString: "1.2.0", legacyState: "IN_REVIEW", legacyOnly: true }]);
    expect(d.kind).toBe("stop");
  });

  it.each(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION"])(
    "FAILS in %s: the marketing version already shipped (I56 lesson)",
    (state) => {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }]);
      expect(d.kind).toBe("fail");
      if (d.kind !== "fail") return;
      expect(d.message).toContain("bump MARKETING_VERSION in mobile/ios/project.yml");
      expect(d.message).toContain("1.2.0");
      expect(d.message).toContain(state);
    },
  );

  it.each(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED", "REJECTED", "READY_FOR_REVIEW", "INVALID_BINARY"])(
    "proceeds to edit in %s",
    (state) => {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }]);
      expect(d.kind).toBe("edit");
      expect(d.kind === "edit" && d.version.id).toBe("v120");
    },
  );

  it.each(["PENDING_CONTRACT", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE", "WAITING_FOR_EXPORT_COMPLIANCE", "SOMETHING_NEW"])(
    "FAILS in unsupported state %s rather than guessing",
    (state) => {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }]);
      expect(d.kind).toBe("fail");
      expect(d.kind === "fail" && d.message).toContain(state);
    },
  );

  it("fails when the version has no readable state at all", () => {
    const vs = versionsFor({ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" });
    const d = decide({ build: build240, versions: [{ ...vs[0]!, state: null }] });
    expect(d.kind).toBe("fail");
  });

  it("with several rows for the build's version, the most advanced state wins (live > in flight > editable)", () => {
    const d = decideFor([
      { id: "vA", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" },
      { id: "vB", versionString: "1.2.0", state: "IN_REVIEW" },
    ]);
    expect(d.kind).toBe("stop");
    expect(d.kind === "stop" && d.version.id).toBe("vB");
  });
});

describe("decide: other versions are looked at too (Apple allows one non-live version at a time)", () => {
  it("1.2.1 build while 1.2.0 waits for review: STOP naming 1.2.0", () => {
    const d = decideFor([{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }], build241);
    expect(d.kind).toBe("stop");
    if (d.kind !== "stop") return;
    expect(d.scope).toBe("other");
    expect(d.version.versionString).toBe("1.2.0");
    expect(d.build).toEqual(build241);
  });

  it("an in-flight other version also stops, whichever in-flight state it is in", () => {
    for (const state of ["IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "ACCEPTED"]) {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }], build241);
      expect(d.kind === "stop" && d.scope).toBe("other");
    }
  });

  it("1.2.1 build with an editable 1.2.0 draft: FAIL naming 1.2.0 and its state", () => {
    const d = decideFor([{ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" }], build241);
    expect(d.kind).toBe("fail");
    if (d.kind !== "fail") return;
    expect(d.message).toContain("1.2.0");
    expect(d.message).toContain("PREPARE_FOR_SUBMISSION");
    expect(d.message).toContain("1.2.1");
  });

  it.each(["REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY", "READY_FOR_REVIEW"])(
    "an other version in %s also fails, naming it",
    (state) => {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }], build241);
      expect(d.kind).toBe("fail");
      expect(d.kind === "fail" && d.message).toContain(state);
    },
  );

  it("live and historical other versions do not block: 1.2.1 is created after a live 1.2.0", () => {
    const d = decideFor(
      [
        { id: "v120", versionString: "1.2.0", state: "READY_FOR_SALE", createdDate: "2026-09-01T00:00:00Z" },
        { id: "v110", versionString: "1.1.0", state: "REPLACED_WITH_NEW_VERSION", createdDate: "2026-08-01T00:00:00Z" },
        { id: "v100", versionString: "1.0.0", state: "REMOVED_FROM_SALE", createdDate: "2026-07-01T00:00:00Z" },
      ],
      build241,
    );
    expect(d.kind).toBe("create");
    expect(d.kind === "create" && d.previousLive?.id).toBe("v120");
  });

  it("the previous live version is the newest live one by creation date", () => {
    const d = decideFor(
      [
        { id: "old", versionString: "1.1.0", state: "READY_FOR_DISTRIBUTION", createdDate: "2026-08-01T00:00:00Z" },
        { id: "new", versionString: "1.2.0", state: "READY_FOR_DISTRIBUTION", createdDate: "2026-09-01T00:00:00Z" },
      ],
      build241,
    );
    expect(d.kind === "create" && d.previousLive?.id).toBe("new");
  });

  it("falls back to the newest replaced version when none is marked live; null when there is no history at all", () => {
    const d = decideFor(
      [
        { id: "a", versionString: "1.0.0", state: "REPLACED_WITH_NEW_VERSION", createdDate: "2026-07-01T00:00:00Z" },
        { id: "b", versionString: "1.1.0", state: "REPLACED_WITH_NEW_VERSION", createdDate: "2026-08-01T00:00:00Z" },
      ],
      build241,
    );
    expect(d.kind === "create" && d.previousLive?.id).toBe("b");
    expect(decideFor([{ id: "x", versionString: "1.0.0", state: "REMOVED_FROM_SALE" }], build241)).toMatchObject({
      kind: "create",
      previousLive: null,
    });
  });

  it("the build's own live version fails with the bump hint even if another version is in flight", () => {
    const d = decideFor(
      [
        { id: "v110", versionString: "1.1.0", state: "READY_FOR_SALE" },
        { id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" },
      ],
      parseNewestBuild(buildsDoc([{ id: "b239", buildNumber: "239", marketingVersion: "1.1.0" }]))!,
    );
    expect(d.kind).toBe("fail");
    expect(d.kind === "fail" && d.message).toContain("bump MARKETING_VERSION in mobile/ios/project.yml");
  });

  it("an editable version for the build still proceeds when no other version is in the way", () => {
    const d = decideFor([
      { id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" },
      { id: "v110", versionString: "1.1.0", state: "READY_FOR_SALE" },
    ]);
    expect(d.kind).toBe("edit");
  });

  it("an other in-flight version beats an editable matching one (stop, never edit)", () => {
    const d = decideFor([
      { id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" },
      { id: "v119", versionString: "1.1.9", state: "IN_REVIEW" },
    ]);
    expect(d.kind === "stop" && d.scope).toBe("other");
  });
});

describe("describeStop", () => {
  const inFlight = versionsFor({ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" })[0]!;

  it("names the state and the build actually attached to the in-flight version", () => {
    const m = describeStop({ build: build240, version: inFlight, scope: "target", attached: { id: "b240", buildNumber: "240" } });
    expect(m).toContain("1.2.0");
    expect(m).toContain("WAITING_FOR_REVIEW");
    expect(m).toContain("build 240");
    expect(m).toMatch(/no changes/i);
    expect(m).not.toMatch(/not the one in review/i);
  });

  it("says the newest build is NOT the one in review when a different build is attached", () => {
    const m = describeStop({ build: build240, version: inFlight, scope: "target", attached: { id: "b239", buildNumber: "239" } });
    expect(m).toContain("239");
    expect(m).toContain("240");
    expect(m).toMatch(/not the one in review/i);
  });

  it("admits when it cannot tell which build is attached", () => {
    const m = describeStop({ build: build240, version: inFlight, scope: "target", attached: null });
    expect(m).toMatch(/could not|no build/i);
    expect(m).toContain("WAITING_FOR_REVIEW");
  });

  it("for another version in flight: names it, its build and the newest build that is waiting", () => {
    const m = describeStop({ build: build241, version: inFlight, scope: "other", attached: { id: "b240", buildNumber: "240" } });
    expect(m).toContain("1.2.0");
    expect(m).toContain("build 240");
    expect(m).toContain("1.2.1");
    expect(m).toContain("241");
    expect(m).toMatch(/no changes/i);
  });
});

// ---------------------------------------------------------------------------------------------

const editable = versionsFor({ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "MANUAL" })[0]!;
const goodReview = parseReviewDetail(reviewDetailDoc({ demoAccountRequired: true, demoAccountName: "review@example.test" }));
const draft = (over: Partial<OpenSubmission> = {}): OpenSubmission => ({ id: "rs1", versionIds: [], otherItemCount: 0, ...over });
const ref = (id: string, state: string): SubmissionRef => ({ id, state });

function details(
  over: Partial<Details> & { locs?: LocalizationFx[]; review?: ReviewDetailFx | null; open?: OpenSubmission } = {},
): Details {
  const { locs, review, open, ...rest } = over;
  return {
    localizations: parseLocalizations(
      localizationsDoc(locs ?? [{ id: "l-gb", locale: "en-GB", whatsNew: "old" }, { id: "l-nl", locale: "nl-NL" }]),
    ),
    attachedBuildId: null,
    reviewDetail: review === undefined ? goodReview : review === null ? null : parseReviewDetail(reviewDetailDoc(review)),
    phasedReleaseId: null,
    submissions: open ? [ref(open.id, "READY_FOR_REVIEW")] : [],
    drafts: open ? [open] : [],
    ...rest,
  };
}

const plan = (d: Details, version: AppVersion = editable) =>
  planEdit({ appId: APP_ID, notes: NOTES, build: build240, version, details: d });
const opsOf = (p: ReturnType<typeof plan>): Op[] => {
  if (p.kind !== "ops") throw new Error(`expected ops, got ${p.kind}: ${p.kind === "fail" ? p.message : ""}`);
  return p.ops;
};

describe("planEdit: an editable version", () => {
  it("sets whatsNew everywhere, attaches the build, sets the release type, removes phased release, then submits (in that order)", () => {
    const ops = opsOf(plan(details({ phasedReleaseId: "ph1" })));
    expect(ops).toEqual([
      { kind: "setWhatsNew", localizationId: "l-gb", locale: "en-GB", text: NOTES },
      { kind: "setWhatsNew", localizationId: "l-nl", locale: "nl-NL", text: NOTES },
      { kind: "attachBuild", versionId: "v120", buildId: "b240", buildNumber: "240" },
      { kind: "setReleaseType", versionId: "v120", releaseType: "AFTER_APPROVAL", from: "MANUAL" },
      { kind: "deletePhasedRelease", phasedReleaseId: "ph1" },
      { kind: "createReviewSubmission", appId: APP_ID },
      { kind: "addSubmissionItem", submissionId: null, versionId: "v120" },
      { kind: "submitReviewSubmission", submissionId: null },
    ]);
  });

  it("skips what is already right: same notes, same build, automatic release, no phased release", () => {
    const already = versionsFor({ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "AFTER_APPROVAL" })[0]!;
    const ops = opsOf(
      plan(details({ locs: [{ id: "l-gb", locale: "en-GB", whatsNew: NOTES }], attachedBuildId: "b240" }), already),
    );
    expect(ops.map((o) => o.kind)).toEqual(["createReviewSubmission", "addSubmissionItem", "submitReviewSubmission"]);
  });

  it("treats notes that differ only by surrounding whitespace as already set", () => {
    const ops = opsOf(plan(details({ locs: [{ id: "l-gb", locale: "en-GB", whatsNew: `  ${NOTES}\n` }] })));
    expect(ops.some((o) => o.kind === "setWhatsNew")).toBe(false);
  });

  it("re-attaches when a different build is attached", () => {
    const ops = opsOf(plan(details({ attachedBuildId: "b-old" })));
    expect(ops).toContainEqual({ kind: "attachBuild", versionId: "v120", buildId: "b240", buildNumber: "240" });
  });

  it("sets the release type when it is unset (null)", () => {
    const unset = versionsFor({ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: null })[0]!;
    expect(opsOf(plan(details(), unset))).toContainEqual({
      kind: "setReleaseType",
      versionId: "v120",
      releaseType: "AFTER_APPROVAL",
      from: null,
    });
  });

  it("a rejected version is edited the same way as a fresh one (when no submission blocks)", () => {
    const rejected = versionsFor({ id: "v120", versionString: "1.2.0", state: "REJECTED" })[0]!;
    expect(opsOf(plan(details(), rejected)).at(-1)).toEqual({ kind: "submitReviewSubmission", submissionId: null });
  });
});

describe("planEdit: review submissions", () => {
  it("reuses an open (draft) submission and adds the version to it", () => {
    const ops = opsOf(plan(details({ open: draft() })));
    expect(ops.some((o) => o.kind === "createReviewSubmission")).toBe(false);
    expect(ops.slice(-2)).toEqual([
      { kind: "addSubmissionItem", submissionId: "rs1", versionId: "v120" },
      { kind: "submitReviewSubmission", submissionId: "rs1" },
    ]);
  });

  it("when the open submission already holds the version, only submits it", () => {
    const ops = opsOf(plan(details({ open: draft({ versionIds: ["v120"] }) })));
    expect(ops.filter((o) => o.kind === "addSubmissionItem")).toEqual([]);
    expect(ops.at(-1)).toEqual({ kind: "submitReviewSubmission", submissionId: "rs1" });
  });

  it("FAILS rather than silently submitting someone else's items in the open submission", () => {
    const p = plan(details({ open: draft({ otherItemCount: 2 }) }));
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/other items/i);
  });

  it("FAILS if the open submission holds a different version", () => {
    expect(plan(details({ open: draft({ versionIds: ["v-other"] }) })).kind).toBe("fail");
  });

  describe("every non-terminal submission state is checked before any change", () => {
    it.each(["UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW"])("FAILS on a submission in %s: resolve or resubmit it", (state) => {
      const p = plan(details({ submissions: [ref("rsX", state)] }));
      expect(p.kind).toBe("fail");
      if (p.kind !== "fail") return;
      expect(p.message).toContain(state);
      expect(p.message).toContain("rsX");
      expect(p.message).toContain("resolve or resubmit it in App Store Connect");
      expect(p.message).not.toMatch(/wait a few minutes/i);
    });

    it.each(["CANCELING", "COMPLETING"])("FAILS on a submission in %s: transient, wait a few minutes and re-run", (state) => {
      const p = plan(details({ submissions: [ref("rsX", state)] }));
      expect(p.kind).toBe("fail");
      if (p.kind !== "fail") return;
      expect(p.message).toContain(state);
      expect(p.message).toContain("rsX");
      expect(p.message).toContain("wait a few minutes and re-run");
      expect(p.message).not.toContain("resolve or resubmit");
    });

    it("still fails when a reusable draft exists next to the blocking submission", () => {
      const p = plan(
        details({ submissions: [ref("rs1", "READY_FOR_REVIEW"), ref("rsX", "UNRESOLVED_ISSUES")], drafts: [draft()] }),
      );
      expect(p.kind).toBe("fail");
      expect(p.kind === "fail" && p.message).toContain("UNRESOLVED_ISSUES");
    });

    it("a READY_FOR_REVIEW draft and a COMPLETE (terminal) submission do not block", () => {
      const p = plan(details({ submissions: [ref("rs0", "COMPLETE"), ref("rs1", "READY_FOR_REVIEW")], drafts: [draft()] }));
      expect(p.kind).toBe("ops");
    });
  });

  describe("chooseOpenSubmission", () => {
    it("prefers the draft that already holds the version, else the first, else null", () => {
      const a: OpenSubmission = { id: "a", versionIds: [], otherItemCount: 0 };
      const b: OpenSubmission = { id: "b", versionIds: ["v120"], otherItemCount: 0 };
      expect(chooseOpenSubmission([a, b], "v120")).toBe(b);
      expect(chooseOpenSubmission([a], "v120")).toBe(a);
      expect(chooseOpenSubmission([], "v120")).toBeNull();
    });
  });
});

describe("planEdit: App Review details (never invented)", () => {
  it("FAILS, with no operations, when there is no review detail resource", () => {
    const p = plan(details({ review: null }));
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/App Review (information|details)/i);
    expect(p.kind === "fail" && p.message).toMatch(/demo account/i);
  });

  it("FAILS when sign-in is not marked as required", () => {
    expect(plan(details({ review: { demoAccountRequired: false, demoAccountName: "review@example.test" } })).kind).toBe("fail");
  });

  it("FAILS when the demo account name is empty", () => {
    expect(plan(details({ review: { demoAccountRequired: true, demoAccountName: "" } })).kind).toBe("fail");
    expect(plan(details({ review: { demoAccountRequired: true, demoAccountName: "   " } })).kind).toBe("fail");
    expect(plan(details({ review: { demoAccountRequired: true, demoAccountName: null } })).kind).toBe("fail");
  });

  it("the failure message does not contain the account name", () => {
    const p = plan(details({ review: { demoAccountRequired: false, demoAccountName: "secret.person@example.test" } }));
    expect(p.kind === "fail" && p.message).not.toContain("secret.person");
  });
});

describe("planEdit: localizations", () => {
  it("FAILS when the version has no localizations (there is nowhere to put the release notes)", () => {
    const p = plan(details({ locs: [] }));
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/localization/i);
  });
});

describe("planCreate: every blocker is checked before the version is created", () => {
  const live = versionsFor({ id: "v120", versionString: "1.2.0", state: "READY_FOR_SALE" })[0]!;
  const base = {
    appId: APP_ID,
    build: build241,
    submissions: [] as SubmissionRef[],
    drafts: [] as OpenSubmission[],
    previousLive: live as AppVersion | null,
    proxyReviewDetail: goodReview,
  };

  it("creates the version when nothing blocks and the proxy review detail is good", () => {
    expect(planCreate(base)).toEqual({
      kind: "ops",
      ops: [{ kind: "createVersion", appId: APP_ID, versionString: "1.2.1" }],
    });
  });

  it.each(["UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW"])("FAILS on a submission in %s: resolve or resubmit it", (state) => {
    const p = planCreate({ ...base, submissions: [ref("rsX", state)] });
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toContain(state);
    expect(p.kind === "fail" && p.message).toContain("resolve or resubmit it in App Store Connect");
  });

  it.each(["CANCELING", "COMPLETING"])("FAILS on a submission in %s: wait a few minutes and re-run", (state) => {
    const p = planCreate({ ...base, submissions: [ref("rsX", state)] });
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toContain(state);
    expect(p.kind === "fail" && p.message).toContain("wait a few minutes and re-run");
    expect(p.kind === "fail" && p.message).not.toContain("resolve or resubmit");
  });

  it("FAILS when an open draft already holds items (the new version could not be added to it safely)", () => {
    const p = planCreate({ ...base, submissions: [ref("rs1", "READY_FOR_REVIEW")], drafts: [draft({ versionIds: ["v-old"] })] });
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/other items/i);
  });

  it("an empty open draft is fine (it will be reused)", () => {
    expect(planCreate({ ...base, submissions: [ref("rs1", "READY_FOR_REVIEW")], drafts: [draft()] }).kind).toBe("ops");
  });

  it("FAILS when the previous live version has no App Review details (the new one would inherit nothing)", () => {
    const p = planCreate({ ...base, proxyReviewDetail: null });
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toContain("1.2.0");
    expect(p.kind === "fail" && p.message).toMatch(/App Review/i);
  });

  it("FAILS when the previous live version has no demo account, naming it but not the account", () => {
    const p = planCreate({
      ...base,
      proxyReviewDetail: parseReviewDetail(reviewDetailDoc({ demoAccountRequired: false, demoAccountName: "secret.person@example.test" })),
    });
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/demo account/i);
    expect(p.kind === "fail" && p.message).not.toContain("secret.person");
  });

  describe("the advice never tells you to edit a live (read-only) version", () => {
    const cases: Array<[string, ReturnType<typeof parseReviewDetail>]> = [
      ["no review detail at all", null],
      ["sign-in not required", parseReviewDetail(reviewDetailDoc({ demoAccountRequired: false, demoAccountName: "x@example.test" }))],
      ["blank demo account name", parseReviewDetail(reviewDetailDoc({ demoAccountRequired: true, demoAccountName: "  " }))],
    ];
    it.each(cases)("%s: create the NEW version, fill in its App Review information, re-run", (_label, proxy) => {
      const p = planCreate({ ...base, proxyReviewDetail: proxy });
      expect(p.kind).toBe("fail");
      if (p.kind !== "fail") return;
      expect(p.message).toMatch(/create version 1\.2\.1 in App Store Connect/i);
      expect(p.message).toMatch(/fill in its App Review information/i);
      expect(p.message).toMatch(/re-run/i);
      expect(p.message).toMatch(/read-only/i);
      expect(p.message).toMatch(/edit path/i);
      // the old, impossible advice ("Open it in App Store Connect and fill in App Review") is gone
      expect(p.message).not.toMatch(/open it in App Store Connect/i);
    });
  });

  it("without a previous live version (first release) there is no proxy to check", () => {
    expect(planCreate({ ...base, previousLive: null, proxyReviewDetail: null }).kind).toBe("ops");
  });
});

describe("describeOp", () => {
  it("renders every operation kind as a one-line, secret-free description", () => {
    const ops: Op[] = [
      { kind: "createVersion", appId: APP_ID, versionString: "1.2.0" },
      { kind: "setWhatsNew", localizationId: "l1", locale: "en-GB", text: NOTES },
      { kind: "attachBuild", versionId: "v120", buildId: "b240", buildNumber: "240" },
      { kind: "setReleaseType", versionId: "v120", releaseType: "AFTER_APPROVAL", from: "MANUAL" },
      { kind: "deletePhasedRelease", phasedReleaseId: "ph1" },
      { kind: "createReviewSubmission", appId: APP_ID },
      { kind: "addSubmissionItem", submissionId: null, versionId: "v120" },
      { kind: "submitReviewSubmission", submissionId: "rs1" },
    ];
    const lines = ops.map(describeOp);
    for (const l of lines) {
      expect(l).not.toBe("");
      expect(l).not.toContain("\n");
    }
    expect(lines[0]).toContain("1.2.0");
    expect(lines[1]).toContain("en-GB");
    expect(lines[2]).toContain("240");
    expect(lines[3]).toContain("AFTER_APPROVAL");
  });
});
