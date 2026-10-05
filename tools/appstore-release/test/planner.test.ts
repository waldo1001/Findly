import { describe, expect, it } from "vitest";
import { parseLocalizations, parseNewestBuild, parseReviewDetail, parseVersions } from "../src/parse";
import {
  chooseOpenSubmission,
  decide,
  describeOp,
  planCreate,
  planEdit,
  type Decision,
  type Details,
  type Op,
} from "../src/planner";
import type { AppVersion, Build, OpenSubmission } from "../src/model";
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

function versionsFor(...vs: VersionFx[]): AppVersion[] {
  return parseVersions(versionsDoc(vs));
}

function decideFor(vs: VersionFx[], build: Build | null = build240): Decision {
  return decide({ build, versions: versionsFor(...vs) });
}

describe("decide — which state is the release in?", () => {
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
    expect(d).toEqual({ kind: "create", build: build240 });
  });

  it("ignores versions with a different version string", () => {
    expect(decideFor([{ id: "v130", versionString: "1.3.0", state: "WAITING_FOR_REVIEW" }]).kind).toBe("create");
  });

  it("STOPs, changing nothing, when 1.2.0 is waiting for review (today's real state)", () => {
    const d = decideFor([{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }]);
    expect(d.kind).toBe("stop");
    if (d.kind !== "stop") return;
    expect(d.message).toContain("1.2.0");
    expect(d.message).toContain("WAITING_FOR_REVIEW");
    expect(d.message).toContain("240");
    expect(d.message).toMatch(/no changes/i);
    expect(d.version.id).toBe("v120");
  });

  it.each(["WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "ACCEPTED", "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE"])(
    "STOPs in %s",
    (state) => {
      const d = decideFor([{ id: "v120", versionString: "1.2.0", state }]);
      expect(d.kind).toBe("stop");
      expect(d.kind === "stop" && d.message).toContain(state);
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

  it("with several matches, the most advanced state wins (live > in flight > editable)", () => {
    const d = decideFor([
      { id: "vA", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" },
      { id: "vB", versionString: "1.2.0", state: "IN_REVIEW" },
    ]);
    expect(d.kind).toBe("stop");
    expect(d.kind === "stop" && d.version.id).toBe("vB");
  });
});

describe("planCreate", () => {
  it("creates the version as automatic-release-after-approval", () => {
    expect(planCreate({ appId: APP_ID, build: build240 })).toEqual([
      { kind: "createVersion", appId: APP_ID, versionString: "1.2.0" },
    ]);
  });
});

// ---------------------------------------------------------------------------------------------

const editable = versionsFor({ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "MANUAL" })[0]!;
const goodReview = parseReviewDetail(reviewDetailDoc({ demoAccountRequired: true, demoAccountName: "review@example.test" }));

function details(over: Partial<Details> & { locs?: LocalizationFx[]; review?: ReviewDetailFx | null } = {}): Details {
  const { locs, review, ...rest } = over;
  return {
    localizations: parseLocalizations(
      localizationsDoc(locs ?? [{ id: "l-gb", locale: "en-GB", whatsNew: "old" }, { id: "l-nl", locale: "nl-NL" }]),
    ),
    attachedBuildId: null,
    reviewDetail: review === undefined ? goodReview : review === null ? null : parseReviewDetail(reviewDetailDoc(review)),
    phasedReleaseId: null,
    openSubmission: null,
    ...rest,
  };
}

const plan = (d: Details, version: AppVersion = editable) =>
  planEdit({ appId: APP_ID, notes: NOTES, build: build240, version, details: d });
const opsOf = (p: ReturnType<typeof plan>): Op[] => {
  if (p.kind !== "ops") throw new Error(`expected ops, got ${p.kind}: ${p.kind === "fail" ? p.message : ""}`);
  return p.ops;
};

describe("planEdit — an editable version", () => {
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

  it("a rejected version is edited the same way as a fresh one", () => {
    const rejected = versionsFor({ id: "v120", versionString: "1.2.0", state: "REJECTED" })[0]!;
    expect(opsOf(plan(details(), rejected)).at(-1)).toEqual({ kind: "submitReviewSubmission", submissionId: null });
  });
});

describe("planEdit — review submissions", () => {
  const open = (over: Partial<OpenSubmission> = {}): OpenSubmission => ({ id: "rs1", versionIds: [], otherItemCount: 0, ...over });

  it("reuses an open (draft) submission and adds the version to it", () => {
    const ops = opsOf(plan(details({ openSubmission: open() })));
    expect(ops.some((o) => o.kind === "createReviewSubmission")).toBe(false);
    expect(ops.slice(-2)).toEqual([
      { kind: "addSubmissionItem", submissionId: "rs1", versionId: "v120" },
      { kind: "submitReviewSubmission", submissionId: "rs1" },
    ]);
  });

  it("when the open submission already holds the version, only submits it", () => {
    const ops = opsOf(plan(details({ openSubmission: open({ versionIds: ["v120"] }) })));
    expect(ops.filter((o) => o.kind === "addSubmissionItem")).toEqual([]);
    expect(ops.at(-1)).toEqual({ kind: "submitReviewSubmission", submissionId: "rs1" });
  });

  it("FAILS rather than silently submitting someone else's items in the open submission", () => {
    const p = plan(details({ openSubmission: open({ otherItemCount: 2 }) }));
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/other items/i);
  });

  it("FAILS if the open submission holds a different version", () => {
    const p = plan(details({ openSubmission: open({ versionIds: ["v-other"] }) }));
    expect(p.kind).toBe("fail");
  });

  describe("chooseOpenSubmission", () => {
    it("prefers the submission that already holds the version, else the first, else null", () => {
      const a: OpenSubmission = { id: "a", versionIds: [], otherItemCount: 0 };
      const b: OpenSubmission = { id: "b", versionIds: ["v120"], otherItemCount: 0 };
      expect(chooseOpenSubmission([a, b], "v120")).toBe(b);
      expect(chooseOpenSubmission([a], "v120")).toBe(a);
      expect(chooseOpenSubmission([], "v120")).toBeNull();
    });
  });
});

describe("planEdit — App Review details (never invented)", () => {
  it("FAILS, with no operations, when there is no review detail resource", () => {
    const p = plan(details({ review: null }));
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/App Review (information|details)/i);
    expect(p.kind === "fail" && p.message).toMatch(/demo account/i);
  });

  it("FAILS when sign-in is not marked as required", () => {
    const p = plan(details({ review: { demoAccountRequired: false, demoAccountName: "review@example.test" } }));
    expect(p.kind).toBe("fail");
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

describe("planEdit — localizations", () => {
  it("FAILS when the version has no localizations (there is nowhere to put the release notes)", () => {
    const p = plan(details({ locs: [] }));
    expect(p.kind).toBe("fail");
    expect(p.kind === "fail" && p.message).toMatch(/localization/i);
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
