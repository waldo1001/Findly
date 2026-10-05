import { generateKeyPairSync } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import type { FetchFn } from "../src/auth";
import { buildJwt, parseServiceAccount } from "../src/auth";
import { run } from "../src/cli";
import productionCurrent from "./fixtures/production-current.json";
import {
  COMMIT,
  EDIT_ID,
  PRODUCTION_RELEASES,
  TOKEN,
  changesAlreadyInReview,
  createFakePlay,
  jsonResponse,
  playError,
  releaseSummaries,
  releaseSummary,
} from "./support/fake-play";
import type { Reply } from "./support/fake-play";

// The CLI glue: env in, exit code + log lines + step summary out. Everything runs against a stub
// `fetch` that serves both Google's token endpoint and the Play API — nothing here has touched the
// real services.

const TOKEN_URI = "https://oauth2.googleapis.com/token";
const NOTES = "Bug fixes and a faster map.";
const T = `/edits/${EDIT_ID}/tracks`;

let privateKeyPem: string;
let saJson: string;

beforeAll(() => {
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  saJson = JSON.stringify({
    type: "service_account",
    client_email: "findly-release@example-project.iam.gserviceaccount.test",
    private_key: privateKeyPem,
    token_uri: TOKEN_URI,
  });
});

interface Harness {
  exitCode: number;
  out: string[];
  /** Values handed to the mask hook (only collected unless `collectMasks` is false). */
  masked: string[];
  summary: string | undefined;
  fetched: string[];
}

async function runCli(
  envOverrides: Record<string, string | undefined> = {},
  playOverrides: Record<string, Reply> = {},
  tokenReply: Reply = jsonResponse({ access_token: TOKEN, expires_in: 3599, token_type: "Bearer" }),
  collectMasks = true,
): Promise<Harness> {
  const fake = createFakePlay(playOverrides);
  const fetched: string[] = [];
  const fetchFn: FetchFn = async (url, init) => {
    fetched.push(`${init?.method ?? "GET"} ${url}`);
    if (url === TOKEN_URI) return tokenReply();
    return fake.fetchFn(url, init);
  };

  const dir = mkdtempSync(join(tmpdir(), "play-release-cli-"));
  const summaryPath = join(dir, "summary.md");
  writeFileSync(summaryPath, "");
  const out: string[] = [];

  const env: Record<string, string | undefined> = {
    PLAY_SERVICE_ACCOUNT_JSON: saJson,
    RELEASE_NOTES: NOTES,
    DRY_RUN: "true",
    GITHUB_STEP_SUMMARY: summaryPath,
    ...envOverrides,
  };

  const masked: string[] = [];
  const exitCode = await run(env, {
    fetchFn,
    now: () => 1_760_000_000_000,
    log: (line) => out.push(line),
    ...(collectMasks ? { mask: (secret: string) => void masked.push(secret) } : {}),
  });
  const summary = readFileSync(summaryPath, "utf8");
  return { exitCode, out, masked, summary: summary === "" ? undefined : summary, fetched };
}

const ASSERTION = () => buildJwt(parseServiceAccount(saJson), 1_760_000_000);

describe("run() — happy paths", () => {
  it("dry run: exits 0, authenticates first, validates, never commits, writes a dry-run summary", async () => {
    const result = await runCli({ DRY_RUN: "true" });
    expect(result.exitCode).toBe(0);
    expect(result.fetched[0]).toBe(`POST ${TOKEN_URI}`);
    expect(result.fetched.some((f) => f.includes(":commit"))).toBe(false);
    expect(result.fetched.some((f) => f.includes(":validate"))).toBe(true);
    expect(result.summary).toMatch(/Dry run/);
    expect(result.summary).toContain("https://play.google.com/console");
  });

  it("real run: commits and writes a committed summary", async () => {
    const result = await runCli({ DRY_RUN: "false" });
    expect(result.exitCode).toBe(0);
    expect(result.fetched.some((f) => f.includes(":commit"))).toBe(true);
    expect(result.summary).toMatch(/Committed/);
  });

  it("nothing to release: exits 0 without committing", async () => {
    const result = await runCli({ DRY_RUN: "false" }, { [`GET ${T}/production`]: jsonResponse(productionCurrent) });
    expect(result.exitCode).toBe(0);
    expect(result.fetched.some((f) => f.includes(":commit"))).toBe(false);
    expect(result.summary).toMatch(/Nothing to release/);
  });

  it("appends to the step summary rather than overwriting it", async () => {
    const dir = mkdtempSync(join(tmpdir(), "play-release-cli-"));
    const summaryPath = join(dir, "summary.md");
    writeFileSync(summaryPath, "## earlier step\n");
    const fake = createFakePlay();
    const fetchFn: FetchFn = async (url, init) =>
      url === TOKEN_URI ? jsonResponse({ access_token: TOKEN })() : fake.fetchFn(url, init);
    await run(
      { PLAY_SERVICE_ACCOUNT_JSON: saJson, RELEASE_NOTES: NOTES, DRY_RUN: "true", GITHUB_STEP_SUMMARY: summaryPath },
      { fetchFn, now: () => 1_760_000_000_000, log: () => undefined },
    );
    const text = readFileSync(summaryPath, "utf8");
    expect(text.startsWith("## earlier step\n")).toBe(true);
    expect(text).toMatch(/Dry run/);
  });

  it("works without GITHUB_STEP_SUMMARY (local run) and just logs", async () => {
    const result = await runCli({ GITHUB_STEP_SUMMARY: undefined });
    expect(result.exitCode).toBe(0);
    expect(result.out.length).toBeGreaterThan(0);
  });

  it("an empty GITHUB_STEP_SUMMARY is treated as unset", async () => {
    const result = await runCli({ GITHUB_STEP_SUMMARY: "" });
    expect(result.exitCode).toBe(0);
  });

  it("changes already in review: exits 0 (a successful run that changed nothing), 'Stopped' summary, no error annotation", async () => {
    const result = await runCli({ DRY_RUN: "false" }, { [COMMIT]: changesAlreadyInReview() });
    expect(result.exitCode).toBe(0);
    expect(result.summary).toMatch(/Stopped/);
    expect(result.summary).toMatch(/changes in review/i);
    expect(result.summary).not.toMatch(/Committed/);
    expect(result.out.some((line) => line.startsWith("::error::"))).toBe(false);
    expect(result.fetched.filter((f) => f.includes(":commit"))).toHaveLength(1);
  });

  it("the committed summary names the release and the production state Play reports", async () => {
    const result = await runCli({ DRY_RUN: "false" });
    expect(result.summary).toContain("1.2.0 (234)");
    expect(result.summary).toContain("IN_REVIEW");
  });

  // Regression for the shape bug: Google's ReleaseSummary has activeArtifacts[].versionCode, not
  // versionCodes[]. Parsed wrongly, the codes were always empty — the summary printed "[none]" and
  // the "nothing to release" row always said "state not reported", losing the very state §5 asks for.
  it("end to end, with Google's real ReleaseSummary shape: the codes and the state reach the summary", async () => {
    const result = await runCli(
      { DRY_RUN: "false" },
      {
        [`GET ${T}/production`]: jsonResponse(productionCurrent),
        [PRODUCTION_RELEASES]: releaseSummaries(releaseSummary("1.2.0 (234)", [234], "NOT_APPROVED")),
      },
    );
    expect(result.exitCode).toBe(0);
    expect(result.summary).toMatch(/Nothing to release/);
    expect(result.summary).toContain("NOT_APPROVED");
    expect(result.summary).toContain("[234]");
    expect(result.summary).not.toContain("[none]");
    expect(result.summary).not.toMatch(/state not reported/i);
  });

  it("any other commit refusal fails with the next step in the annotation", async () => {
    const result = await runCli(
      { DRY_RUN: "false" },
      { [COMMIT]: playError(400, "Changes cannot be sent for review automatically.") },
    );
    expect(result.exitCode).toBe(1);
    const annotation = result.out.find((line) => line.startsWith("::error::"))!;
    expect(annotation).toContain("Changes cannot be sent for review automatically.");
    expect(annotation).toContain("Publishing overview");
    expect(annotation).toContain("Send changes for review");
  });
});

describe("run() — derived credentials are masked, the token endpoint is pinned", () => {
  it("masks the signed assertion first and the access token second, before anything else is logged", async () => {
    const result = await runCli({ DRY_RUN: "true" });
    expect(result.masked).toEqual([ASSERTION(), TOKEN]);
  });

  it("without an injected hook, masks go out as ::add-mask:: workflow commands (assertion, then token)", async () => {
    const result = await runCli({ DRY_RUN: "true" }, {}, undefined, false);
    const masks = result.out.filter((line) => line.startsWith("::add-mask::"));
    expect(masks).toEqual([`::add-mask::${ASSERTION()}`, `::add-mask::${TOKEN}`]);
    // ...and they are the very first thing emitted, ahead of any narration.
    expect(result.out.indexOf(masks[0]!)).toBeLessThan(result.out.findIndex((l) => !l.startsWith("::add-mask::")));
  });

  it("a key file whose token_uri is not Google's is rejected before any network call, without echoing it", async () => {
    const doctored = JSON.stringify({ ...JSON.parse(saJson), token_uri: "https://evil.example/collect" });
    const result = await runCli({ PLAY_SERVICE_ACCOUNT_JSON: doctored });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.masked).toEqual([]);
    const all = [...result.out, result.summary ?? ""].join("\n");
    expect(all).toMatch(/token_uri/);
    expect(all).not.toContain("evil.example");
  });
});

describe("run() — input validation happens before any network call", () => {
  it.each([undefined, "", "yes", "TRUE", "1", " true "])("DRY_RUN=%j is rejected (fail closed, no guessing)", async (value) => {
    const result = await runCli({ DRY_RUN: value });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.out.join("\n")).toMatch(/DRY_RUN/);
    expect(result.summary).toMatch(/Failed/);
  });

  it.each([undefined, "", "   ", "a".repeat(501)])("RELEASE_NOTES=%j is rejected before authenticating", async (value) => {
    const result = await runCli({ RELEASE_NOTES: value });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.out.join("\n")).toMatch(/notes/i);
  });

  it("an unparsable service-account JSON is rejected without echoing it", async () => {
    const result = await runCli({ PLAY_SERVICE_ACCOUNT_JSON: "{ not json sensitive-marker" });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    const all = [...result.out, result.summary ?? ""].join("\n");
    expect(all).toMatch(/PLAY_SERVICE_ACCOUNT_JSON/);
    expect(all).not.toContain("sensitive-marker");
  });

  it("a missing service-account JSON is rejected", async () => {
    const result = await runCli({ PLAY_SERVICE_ACCOUNT_JSON: undefined });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
  });
});

describe("run() — failures", () => {
  it("a rejected token exchange fails the run before any Play call", async () => {
    const result = await runCli({}, {}, jsonResponse({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, 400));
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([`POST ${TOKEN_URI}`]);
    expect(result.out.join("\n")).toMatch(/invalid_grant/);
    expect(result.summary).toMatch(/Failed/);
  });

  it("a refused commit fails the run and surfaces Play's message in the log and the summary", async () => {
    const reason = "Changes cannot be sent for review automatically.";
    const result = await runCli({ DRY_RUN: "false" }, { [COMMIT]: playError(400, reason) });
    expect(result.exitCode).toBe(1);
    expect(result.out.join("\n")).toContain(reason);
    expect(result.summary).toContain(reason);
    expect(result.summary).toMatch(/Failed/);
    expect(result.summary).not.toMatch(/Committed/);
  });

  it("emits a GitHub error annotation for a failure", async () => {
    const result = await runCli({ RELEASE_NOTES: "" });
    expect(result.out.some((line) => line.startsWith("::error::"))).toBe(true);
  });

  it("escapes the annotation so a hostile message cannot inject workflow commands", async () => {
    const hostile = "boom\n::add-mask::everything 100%\r::set-env::X";
    const result = await runCli({ DRY_RUN: "false" }, { [COMMIT]: playError(400, hostile) });
    const annotation = result.out.find((line) => line.startsWith("::error::"))!;
    expect(annotation).not.toMatch(/[\r\n]/);
    expect(annotation).toContain("%0A");
    expect(annotation).toContain("%0D");
    expect(annotation).toContain("100%25");
    // No log line other than the annotation itself starts a workflow command.
    expect(result.out.filter((line) => line.startsWith("::"))).toHaveLength(1);
  });

  it("a hostile message in a non-fatal warning cannot start a workflow command either", async () => {
    const result = await runCli(
      { DRY_RUN: "true" },
      { [`DELETE /edits/${EDIT_ID}`]: playError(500, "oops\n::add-mask::everything", "INTERNAL") },
    );
    expect(result.exitCode).toBe(0);
    expect(result.out.some((line) => line.includes("could not delete"))).toBe(true);
    expect(result.out.filter((line) => line.startsWith("::"))).toEqual([]);
    expect(result.out.every((line) => !/[\r\n]/.test(line))).toBe(true);
  });

  it("still exits non-zero when the summary file cannot be written", async () => {
    const result = await runCli({ GITHUB_STEP_SUMMARY: "/nonexistent-dir/summary.md", RELEASE_NOTES: "" });
    expect(result.exitCode).toBe(1);
    expect(result.out.join("\n")).toMatch(/summary/i);
  });
});

describe("run() — secrets never leave the process", () => {
  it("no log line or summary contains the key, the assertion, the token or the raw JSON", async () => {
    for (const overrides of [{ DRY_RUN: "true" }, { DRY_RUN: "false" }, { RELEASE_NOTES: "" }]) {
      const result = await runCli(overrides);
      const everything = [...result.out, result.summary ?? ""].join("\n");
      expect(everything).not.toContain(TOKEN);
      expect(everything).not.toContain(ASSERTION());
      expect(everything).not.toContain(saJson);
      expect(everything).not.toContain("PRIVATE KEY");
      expect(everything).not.toContain(privateKeyPem.split("\n")[1]!);
      expect(everything).not.toContain("assertion");
    }
  });

  it("no secret leaks when a Play call fails mid-flight", async () => {
    const result = await runCli({ DRY_RUN: "false" }, { [`PUT ${T}/production`]: playError(403, "The caller does not have permission", "PERMISSION_DENIED") });
    const everything = [...result.out, result.summary ?? ""].join("\n");
    expect(everything).not.toContain(TOKEN);
    expect(everything).not.toContain("PRIVATE KEY");
  });
});
