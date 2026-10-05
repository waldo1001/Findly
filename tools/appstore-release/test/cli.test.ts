import { generateKeyPairSync, verify } from "node:crypto";
import { describe, expect, it } from "vitest";
import { runCli } from "../src/main";
import {
  APP_ID,
  buildLinkageDoc,
  buildsDoc,
  errorDoc,
  localizationsDoc,
  phasedLinkageDoc,
  reviewDetailDoc,
  singleVersionDoc,
  submissionsDoc,
  versionsDoc,
  type VersionFx,
} from "./fixtures";
import { createStubFetch, on, type Route } from "./stubFetch";

const keys = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const pem = keys.privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const pemBody = pem.split("\n").filter((l) => !l.startsWith("-----") && l.length > 0).join("");

const ENV = {
  ASC_KEY_ID: "FAKEKEY123",
  ASC_ISSUER_ID: "11111111-2222-3333-4444-555555555555",
  ASC_API_KEY_P8: Buffer.from(pem).toString("base64"),
  RELEASE_NOTES: "Faster map refresh and a fix for ghost devices.",
  DRY_RUN: "true",
};

function routes(versions: VersionFx[]): Route[] {
  const v = versions[0] ?? { id: "vNEW", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" };
  return [
    on("GET", "/v1/builds", { body: buildsDoc([{ id: "b240", buildNumber: "240", marketingVersion: "1.2.0" }]) }),
    on("GET", `/v1/apps/${APP_ID}/appStoreVersions`, { body: versionsDoc(versions) }),
    on("GET", `/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations`, { body: localizationsDoc([{ id: "l1", locale: "en-GB" }]) }),
    on("GET", `/v1/appStoreVersions/${v.id}/relationships/build`, { body: buildLinkageDoc(null) }),
    on("GET", `/v1/appStoreVersions/${v.id}/appStoreReviewDetail`, {
      body: reviewDetailDoc({ demoAccountRequired: true, demoAccountName: "review@example.test" }),
    }),
    on("GET", `/v1/appStoreVersions/${v.id}/relationships/appStoreVersionPhasedRelease`, { body: phasedLinkageDoc(null) }),
    on("GET", "/v1/reviewSubmissions", { body: submissionsDoc([]) }),
    on("GET", `/v1/appStoreVersions/${v.id}`, { body: singleVersionDoc({ ...v, state: "WAITING_FOR_REVIEW" }) }),
    on("POST", "/v1/appStoreVersions", { status: 201, body: singleVersionDoc(v) }),
    on("PATCH", "/v1/appStoreVersionLocalizations/l1", { body: { data: { id: "l1" } } }),
    on("PATCH", `/v1/appStoreVersions/${v.id}/relationships/build`, { status: 204 }),
    on("PATCH", `/v1/appStoreVersions/${v.id}`, { body: { data: { id: v.id } } }),
    on("POST", "/v1/reviewSubmissions", { status: 201, body: { data: { id: "rs1" } } }),
    on("POST", "/v1/reviewSubmissionItems", { status: 201, body: { data: { id: "i1" } } }),
    on("PATCH", "/v1/reviewSubmissions/rs1", { body: { data: { id: "rs1" } } }),
  ];
}

async function cli(envOver: Record<string, string | undefined>, rs: Route[]) {
  const stub = createStubFetch(rs);
  const out: string[] = [];
  const summaries: string[] = [];
  const code = await runCli({
    env: { ...ENV, ...envOver },
    fetch: stub.fetch,
    log: (l) => out.push(l),
    writeSummary: (md) => summaries.push(md),
  });
  return { code, stub, out: out.join("\n"), summary: summaries.join("\n") };
}

describe("runCli", () => {
  it("DRY_RUN against the real current state (1.2.0 waiting for review): exit 0, GET only, state reported", async () => {
    const r = await cli({}, routes([{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }]));
    expect(r.code).toBe(0);
    expect(r.stub.calls.every((c) => c.method === "GET")).toBe(true);
    expect(r.summary).toContain("WAITING_FOR_REVIEW");
    expect(r.summary).toContain("https://appstoreconnect.apple.com/apps/6797994768/distribution");
    expect(r.out).toContain("WAITING_FOR_REVIEW");
  });

  it("signs requests with a valid ES256 token that carries the key id and issuer", async () => {
    const r = await cli({}, routes([{ id: "v120", versionString: "1.2.0", state: "WAITING_FOR_REVIEW" }]));
    const auth = r.stub.calls[0]!.headers.authorization!;
    expect(auth).toMatch(/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    const [h, p, s] = auth.slice("Bearer ".length).split(".") as [string, string, string];
    expect(JSON.parse(Buffer.from(h, "base64url").toString())).toEqual({ alg: "ES256", kid: "FAKEKEY123", typ: "JWT" });
    expect(JSON.parse(Buffer.from(p, "base64url").toString()).iss).toBe(ENV.ASC_ISSUER_ID);
    const ok = verify("sha256", Buffer.from(`${h}.${p}`), { key: keys.publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s, "base64url"));
    expect(ok).toBe(true);
  });

  it("never prints the key, the token or the issuer's key material to the log or the summary", async () => {
    const r = await cli({}, routes([{ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" }]));
    const token = r.stub.calls[0]!.headers.authorization!.slice("Bearer ".length);
    for (const text of [r.out, r.summary]) {
      expect(text).not.toContain(pemBody);
      expect(text).not.toContain(ENV.ASC_API_KEY_P8);
      expect(text).not.toContain(token);
      expect(text).not.toMatch(/BEGIN [A-Z ]*PRIVATE KEY/);
    }
  });

  it("DRY_RUN on an editable version: exit 0, still GET only, summary lists the planned steps", async () => {
    const r = await cli({}, routes([{ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION", releaseType: "MANUAL" }]));
    expect(r.code).toBe(0);
    expect(r.stub.calls.every((c) => c.method === "GET")).toBe(true);
    expect(r.summary).toMatch(/dry run/i);
    expect(r.summary).toContain("Attach build 240");
  });

  it("a live run submits and exits 0", async () => {
    const r = await cli({ DRY_RUN: "false" }, routes([{ id: "v120", versionString: "1.2.0", state: "PREPARE_FOR_SUBMISSION" }]));
    expect(r.code).toBe(0);
    expect(r.stub.sequence()).toContain("PATCH /v1/reviewSubmissions/rs1");
    expect(r.summary).toContain("WAITING_FOR_REVIEW");
  });

  it("an already-live version exits 1 with the bump hint in the log and the summary", async () => {
    const r = await cli({ DRY_RUN: "false" }, routes([{ id: "v120", versionString: "1.2.0", state: "READY_FOR_SALE" }]));
    expect(r.code).toBe(1);
    expect(r.out).toContain("bump MARKETING_VERSION in mobile/ios/project.yml");
    expect(r.summary).toContain("bump MARKETING_VERSION in mobile/ios/project.yml");
    expect(r.stub.calls.every((c) => c.method === "GET")).toBe(true);
  });

  it("an API error exits 1 and surfaces Apple's detail", async () => {
    const r = await cli({}, [on("GET", "/v1/builds", { status: 401, body: errorDoc(401, "NOT_AUTHORIZED", "Provide a properly configured and signed bearer token.") })]);
    expect(r.code).toBe(1);
    expect(r.out).toContain("Provide a properly configured and signed bearer token.");
    expect(r.summary).toContain("Provide a properly configured and signed bearer token.");
  });

  it("bad configuration exits 1 before any network call, naming the problem", async () => {
    for (const over of [{ DRY_RUN: "maybe" }, { RELEASE_NOTES: "" }, { ASC_KEY_ID: undefined }, { ASC_API_KEY_P8: "junk" }]) {
      const r = await cli(over, routes([]));
      expect(r.code).toBe(1);
      expect(r.stub.calls).toHaveLength(0);
      expect(r.out).toMatch(/DRY_RUN|RELEASE_NOTES|ASC_KEY_ID|ASC_API_KEY_P8/);
    }
  });

  it("neutralises GitHub workflow commands smuggled into log text", async () => {
    const r = await cli({}, [
      on("GET", "/v1/builds", { status: 400, body: errorDoc(400, "X", "bad\n::add-mask::oops\r\n::error::spoof") }),
    ]);
    for (const line of r.out.split("\n")) expect(line.startsWith("::")).toBe(false);
  });
});
