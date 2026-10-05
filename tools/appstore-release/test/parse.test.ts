import { describe, expect, it } from "vitest";
import {
  parseBuildRef,
  parseLinkageId,
  parseLocalizations,
  parseNewestBuild,
  parseOpenSubmission,
  parseReviewDetail,
  parseSubmissions,
  parseVersions,
} from "../src/parse";
import {
  buildLinkageDoc,
  buildRefDoc,
  buildsDoc,
  localizationsDoc,
  phasedLinkageDoc,
  reviewDetailDoc,
  submissionItemsDoc,
  submissionsDoc,
  versionsDoc,
} from "./fixtures";

describe("parseNewestBuild", () => {
  it("returns the first build with its build number and marketing version from the included preReleaseVersion", () => {
    const doc = buildsDoc([
      { id: "b240", buildNumber: "240", marketingVersion: "1.2.0", uploadedDate: "2026-10-05T09:12:00-07:00" },
      { id: "b239", buildNumber: "239", marketingVersion: "1.1.0" },
    ]);
    expect(parseNewestBuild(doc)).toEqual({
      id: "b240",
      buildNumber: "240",
      marketingVersion: "1.2.0",
      uploadedDate: "2026-10-05T09:12:00-07:00",
    });
  });

  it("returns null when there is no VALID build", () => {
    expect(parseNewestBuild(buildsDoc([]))).toBeNull();
  });

  it("returns null for a build that is not VALID, even if the filter let it through", () => {
    expect(parseNewestBuild(buildsDoc([{ id: "b1", buildNumber: "1", marketingVersion: "1.0.0", processingState: "PROCESSING" }]))).toBeNull();
  });

  it("marketingVersion is null when the preReleaseVersion was not included", () => {
    const b = parseNewestBuild(buildsDoc([{ id: "b1", buildNumber: "7" }]));
    expect(b?.marketingVersion).toBeNull();
  });
});

describe("parseVersions", () => {
  it("reads appVersionState, falling back to the deprecated appStoreState", () => {
    const doc = versionsDoc([
      { id: "v1", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" },
      { id: "v2", versionString: "1.1.0", legacyState: "READY_FOR_SALE", legacyOnly: true },
    ]);
    expect(parseVersions(doc)).toEqual([
      { id: "v1", versionString: "1.2.0", state: "WAITING_FOR_REVIEW", releaseType: "AFTER_APPROVAL", createdDate: "2026-10-04T08:00:00-07:00" },
      { id: "v2", versionString: "1.1.0", state: "READY_FOR_SALE", releaseType: "AFTER_APPROVAL", createdDate: "2026-10-04T08:00:00-07:00" },
    ]);
  });

  it("keeps a null releaseType", () => {
    const [v] = parseVersions(versionsDoc([{ id: "v1", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: null }]));
    expect(v?.releaseType).toBeNull();
  });
});

describe("parseLocalizations", () => {
  it("maps id, locale and whatsNew (null when unset)", () => {
    const doc = localizationsDoc([
      { id: "l1", locale: "en-GB", whatsNew: "old text" },
      { id: "l2", locale: "nl-NL" },
    ]);
    expect(parseLocalizations(doc)).toEqual([
      { id: "l1", locale: "en-GB", whatsNew: "old text" },
      { id: "l2", locale: "nl-NL", whatsNew: null },
    ]);
  });
});

describe("parseLinkageId", () => {
  it("returns the related id, or null for absent data / absent document", () => {
    expect(parseLinkageId(buildLinkageDoc("b240"))).toBe("b240");
    expect(parseLinkageId(buildLinkageDoc(null))).toBeNull();
    expect(parseLinkageId(phasedLinkageDoc("p1"))).toBe("p1");
    expect(parseLinkageId(null)).toBeNull();
  });
});

describe("parseReviewDetail", () => {
  it("reads the demo-account flags", () => {
    expect(parseReviewDetail(reviewDetailDoc({ demoAccountRequired: true, demoAccountName: "review@example.test" }))).toEqual({
      demoAccountRequired: true,
      demoAccountName: "review@example.test",
    });
  });

  it("is null when the resource is absent (404 or data: null)", () => {
    expect(parseReviewDetail(null)).toBeNull();
    expect(parseReviewDetail(reviewDetailDoc(null))).toBeNull();
  });
});

describe("review submissions", () => {
  it("parseSubmissions lists id and state", () => {
    expect(parseSubmissions(submissionsDoc([{ id: "rs1", state: "READY_FOR_REVIEW" }, { id: "rs2", state: "UNRESOLVED_ISSUES" }]))).toEqual([
      { id: "rs1", state: "READY_FOR_REVIEW" },
      { id: "rs2", state: "UNRESOLVED_ISSUES" },
    ]);
    expect(parseSubmissions(submissionsDoc([]))).toEqual([]);
  });

  it("parseOpenSubmission separates version items from other items", () => {
    const doc = submissionItemsDoc([{ id: "i1", versionId: "v-120" }, { id: "i2" }, { id: "i3" }]);
    expect(parseOpenSubmission("rs1", doc)).toEqual({ id: "rs1", versionIds: ["v-120"], otherItemCount: 2 });
  });

  it("an empty submission has no items", () => {
    expect(parseOpenSubmission("rs1", submissionItemsDoc([]))).toEqual({ id: "rs1", versionIds: [], otherItemCount: 0 });
  });
});

describe("parseBuildRef (GET /v1/appStoreVersions/{id}/build)", () => {
  it("returns the attached build's id and build number", () => {
    expect(parseBuildRef(buildRefDoc("b239", "239"))).toEqual({ id: "b239", buildNumber: "239" });
  });

  it("is null when no build is attached (data: null) or the document is absent (404)", () => {
    expect(parseBuildRef(buildRefDoc(null))).toBeNull();
    expect(parseBuildRef(null)).toBeNull();
  });
});
