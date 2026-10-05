import { generateKeyPairSync } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import type { FetchFn } from "../src/auth";
import { buildJwt, parseServiceAccount } from "../src/auth";
import { run } from "../src/cli";
import {
  COMMIT,
  COMMIT_UNSENT,
  DELETE_EDIT,
  EDIT_ID,
  INTERNAL_PUT,
  TOKEN,
  UPLOAD,
  UPLOADED_VERSION_CODE,
  changesAlreadyInReview,
  changesAreSentAutomatically,
  changesCannotBeSentAutomatically,
  createFakePlay,
  internalUploadRoutes,
  jsonResponse,
  playError,
} from "./support/fake-play";
import type { Reply } from "./support/fake-play";

// The CLI in upload-internal mode (docs/store-readiness.md §5, "Android internal-track upload (A59)"):
// env in, exit code + log lines + step summary out. Everything runs against a stub `fetch` serving both
// Google's token endpoint and the Play API — nothing here has touched the real services. The bundle is
// a few fixture bytes in a temp file, not a real AAB.

const TOKEN_URI = "https://oauth2.googleapis.com/token";
const NOTICE =
  "::notice::production review in progress — internal upload deferred; the next main build after the review uploads";
const AAB_MARKER = "AAB-FIXTURE-MARKER-0123456789";

let privateKeyPem: string;
let saJson: string;
let workDir: string;
let aabPath: string;

beforeAll(() => {
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  saJson = JSON.stringify({
    type: "service_account",
    client_email: "findly-release@example-project.iam.gserviceaccount.test",
    private_key: privateKeyPem,
    token_uri: TOKEN_URI,
  });
  workDir = mkdtempSync(join(tmpdir(), "play-upload-internal-"));
  aabPath = join(workDir, "app-release.aab");
  writeFileSync(aabPath, `PK\u0003\u0004${AAB_MARKER}`);
});

interface Harness {
  exitCode: number;
  out: string[];
  masked: string[];
  summary: string | undefined;
  /** "METHOD url" for every request, token endpoint included. */
  fetched: string[];
  /** "METHOD /path" of the Play requests only (see fake-play). */
  play: string[];
  playCalls: ReturnType<typeof createFakePlay>["calls"];
}

async function runCli(
  envOverrides: Record<string, string | undefined> = {},
  playOverrides: Record<string, Reply> = {},
  tokenReply: Reply = jsonResponse({ access_token: TOKEN, expires_in: 3599, token_type: "Bearer" }),
  collectMasks = true,
): Promise<Harness> {
  const fake = createFakePlay({ ...internalUploadRoutes(), ...playOverrides });
  const fetched: string[] = [];
  const fetchFn: FetchFn = async (url, init) => {
    fetched.push(`${init?.method ?? "GET"} ${url}`);
    if (url === TOKEN_URI) return tokenReply();
    return fake.fetchFn(url, init);
  };

  const dir = mkdtempSync(join(tmpdir(), "play-upload-internal-cli-"));
  const summaryPath = join(dir, "summary.md");
  writeFileSync(summaryPath, "");
  const out: string[] = [];

  const env: Record<string, string | undefined> = {
    PLAY_SERVICE_ACCOUNT_JSON: saJson,
    PLAY_RELEASE_MODE: "upload-internal",
    AAB_PATH: aabPath,
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
  return { exitCode, out, masked, summary: summary === "" ? undefined : summary, fetched, play: fake.sequence(), playCalls: fake.calls };
}

const ASSERTION = () => buildJwt(parseServiceAccount(saJson), 1_760_000_000);
const OPEN = ["POST /edits", UPLOAD, INTERNAL_PUT];
const annotations = (out: string[], kind: string): string[] => out.filter((line) => line.startsWith(`::${kind}::`));

describe("run() upload-internal — committed", () => {
  it("exits 0: authenticates first, uploads, sets the internal track, commits; no annotations", async () => {
    const result = await runCli();
    expect(result.exitCode).toBe(0);
    expect(result.fetched[0]).toBe(`POST ${TOKEN_URI}`);
    expect(result.play).toEqual([...OPEN, COMMIT]);
    expect(annotations(result.out, "error")).toEqual([]);
    expect(annotations(result.out, "notice")).toEqual([]);
  });

  it("uploads the file named by AAB_PATH, byte for byte", async () => {
    const result = await runCli();
    const upload = result.playCalls.find((c) => c.path.includes("/bundles"))!;
    expect(Buffer.from(upload.bytes ?? []).toString("latin1")).toBe(`PK\u0003\u0004${AAB_MARKER}`);
    expect(upload.headers["content-type"]).toBe("application/octet-stream");
  });

  it("writes a short summary: version code, internal track, committed", async () => {
    const result = await runCli();
    expect(result.summary).toMatch(/Committed/);
    expect(result.summary).toContain(String(UPLOADED_VERSION_CODE));
    expect(result.summary).toMatch(/Internal testing/);
    expect(result.summary).toContain("https://play.google.com/console");
  });

  it("appends to the step summary rather than overwriting it", async () => {
    const dir = mkdtempSync(join(tmpdir(), "play-upload-internal-cli-"));
    const summaryPath = join(dir, "summary.md");
    writeFileSync(summaryPath, "## earlier step\n");
    const result = await runCli({ GITHUB_STEP_SUMMARY: summaryPath });
    expect(result.exitCode).toBe(0);
    const text = readFileSync(summaryPath, "utf8");
    expect(text.startsWith("## earlier step\n")).toBe(true);
    expect(text).toMatch(/Committed/);
  });

  it("works without GITHUB_STEP_SUMMARY (local run) and just logs", async () => {
    const result = await runCli({ GITHUB_STEP_SUMMARY: undefined });
    expect(result.exitCode).toBe(0);
    expect(result.out.length).toBeGreaterThan(0);
  });

  it("needs neither RELEASE_NOTES nor DRY_RUN: they are release-mode inputs", async () => {
    const result = await runCli({ RELEASE_NOTES: undefined, DRY_RUN: undefined });
    expect(result.exitCode).toBe(0);
  });

  it("an unrelated RELEASE_NOTES in the environment is ignored (never sent anywhere)", async () => {
    const result = await runCli({ RELEASE_NOTES: "should-never-appear-in-any-request" });
    expect(result.exitCode).toBe(0);
    expect(JSON.stringify(result.playCalls.map((c) => c.body))).not.toContain("should-never-appear-in-any-request");
  });
});

describe("run() upload-internal — production review in progress: deferred, exit 0", () => {
  it("emits the ::notice:: exactly, no ::error::, deletes the edit, exits 0", async () => {
    const result = await runCli({}, { [COMMIT]: changesAlreadyInReview() });
    expect(result.exitCode).toBe(0);
    expect(annotations(result.out, "notice")).toEqual([NOTICE]);
    expect(annotations(result.out, "error")).toEqual([]);
    expect(result.play).toEqual([...OPEN, COMMIT, DELETE_EDIT]);
  });

  it("never cancels the review: one commit, ERROR_IF_IN_REVIEW, no changesNotSentForReview", async () => {
    const result = await runCli({}, { [COMMIT]: changesAlreadyInReview() });
    const commits = result.fetched.filter((f) => f.includes(":commit"));
    expect(commits).toHaveLength(1);
    expect(commits[0]).toContain("changesInReviewBehavior=ERROR_IF_IN_REVIEW");
    expect(commits[0]).not.toContain("changesNotSentForReview");
  });

  it("the summary says 'Deferred', not 'Committed' and not 'Failed'", async () => {
    const result = await runCli({}, { [COMMIT]: changesAlreadyInReview() });
    expect(result.summary).toMatch(/Deferred/);
    expect(result.summary).not.toMatch(/Committed|Failed/);
  });

  it("the notice is a single physical line (escaped like the error annotation)", async () => {
    const result = await runCli({}, { [COMMIT]: changesAlreadyInReview() });
    const notice = annotations(result.out, "notice")[0]!;
    expect(notice).not.toMatch(/[\r\n]/);
    // And nothing else in the log starts a workflow command.
    expect(result.out.filter((l) => l.startsWith("::"))).toEqual([notice]);
  });
});

describe("run() upload-internal — Play wants changesNotSentForReview: one retry", () => {
  it("retry commits: exit 0, two commits in order, edit kept, summary says not sent for review", async () => {
    const result = await runCli(
      {},
      { [COMMIT]: changesCannotBeSentAutomatically(), [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) },
    );
    expect(result.exitCode).toBe(0);
    expect(result.play).toEqual([...OPEN, COMMIT, COMMIT_UNSENT]);
    expect(result.summary).toMatch(/Committed/);
    expect(result.summary).toMatch(/not sent for review/i);
    expect(annotations(result.out, "error")).toEqual([]);
    expect(annotations(result.out, "notice")).toEqual([]);
  });

  it("retry fails: exit 1, the error annotation carries Play's message, edit deleted, summary 'Failed'", async () => {
    const result = await runCli(
      {},
      { [COMMIT]: changesCannotBeSentAutomatically(), [COMMIT_UNSENT]: playError(400, "Version code 235 is invalid.") },
    );
    expect(result.exitCode).toBe(1);
    expect(annotations(result.out, "error")[0]).toContain("Version code 235 is invalid.");
    expect(result.play).toEqual([...OPEN, COMMIT, COMMIT_UNSENT, DELETE_EDIT]);
    expect(result.summary).toMatch(/Failed/);
    expect(result.summary).not.toMatch(/Committed/);
  });

  it("the opposite refusal ('must not be set') fails the run — it is not retried with the flag", async () => {
    const result = await runCli({}, { [COMMIT]: changesAreSentAutomatically() });
    expect(result.exitCode).toBe(1);
    expect(result.fetched.some((f) => f.includes("changesNotSentForReview"))).toBe(false);
    expect(annotations(result.out, "error")[0]).toContain("must not be set");
  });
});

describe("run() upload-internal — failures", () => {
  it("the upload fails: exit 1 with Play's message in the annotation, nothing set or committed, edit deleted", async () => {
    const result = await runCli({}, { [UPLOAD]: playError(400, "Version code 235 has already been used.") });
    expect(result.exitCode).toBe(1);
    expect(annotations(result.out, "error")[0]).toContain("Version code 235 has already been used.");
    expect(result.play).toEqual(["POST /edits", UPLOAD, DELETE_EDIT]);
    expect(result.summary).toMatch(/Failed/);
    expect(result.summary).toContain("Version code 235 has already been used.");
  });

  it("setting the track fails: exit 1, no commit, edit deleted", async () => {
    const result = await runCli({}, { [INTERNAL_PUT]: playError(403, "The caller does not have permission", "PERMISSION_DENIED") });
    expect(result.exitCode).toBe(1);
    expect(result.play).toEqual([...OPEN, DELETE_EDIT]);
    expect(annotations(result.out, "error")[0]).toContain("does not have permission");
  });

  it("any other commit refusal fails (no Play Console 'next step' advice — that is the release job's)", async () => {
    const result = await runCli({}, { [COMMIT]: playError(400, "Version code 235 has already been used.") });
    expect(result.exitCode).toBe(1);
    expect(result.play).toEqual([...OPEN, COMMIT, DELETE_EDIT]);
    expect(annotations(result.out, "error")[0]).not.toContain("Publishing overview");
  });

  it("a rejected token exchange fails the run before any Play call", async () => {
    const result = await runCli({}, {}, jsonResponse({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, 400));
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([`POST ${TOKEN_URI}`]);
    expect(result.out.join("\n")).toMatch(/invalid_grant/);
  });

  it("escapes the annotation so a hostile Play message cannot inject workflow commands", async () => {
    const hostile = "boom\n::add-mask::everything 100%\r::set-env::X";
    const result = await runCli({}, { [COMMIT]: playError(400, hostile) });
    const annotation = annotations(result.out, "error")[0]!;
    expect(annotation).not.toMatch(/[\r\n]/);
    expect(annotation).toContain("%0A");
    expect(annotation).toContain("%0D");
    expect(annotation).toContain("100%25");
    expect(result.out.filter((line) => line.startsWith("::"))).toHaveLength(1);
  });

  it("a hostile message in a non-fatal cleanup warning cannot start a workflow command either", async () => {
    const result = await runCli(
      {},
      { [COMMIT]: changesAlreadyInReview(), [DELETE_EDIT]: playError(500, "oops\n::add-mask::everything", "INTERNAL") },
    );
    expect(result.exitCode).toBe(0);
    expect(result.out.some((l) => /could not delete/i.test(l))).toBe(true);
    expect(result.out.filter((l) => l.startsWith("::"))).toEqual([NOTICE]);
    expect(result.out.every((l) => !/[\r\n]/.test(l))).toBe(true);
  });

  it("still exits non-zero when the summary file cannot be written", async () => {
    const result = await runCli({ GITHUB_STEP_SUMMARY: "/nonexistent-dir/summary.md", AAB_PATH: undefined });
    expect(result.exitCode).toBe(1);
    expect(result.out.join("\n")).toMatch(/summary/i);
  });
});

describe("run() upload-internal — input is validated before any network call", () => {
  it("AAB_PATH unset: refused, nothing fetched (not even a token)", async () => {
    const result = await runCli({ AAB_PATH: undefined });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.masked).toEqual([]);
    expect(result.out.join("\n")).toMatch(/AAB_PATH/);
    expect(result.summary).toMatch(/Failed/);
  });

  it.each(["", "   "])("AAB_PATH=%j: refused, nothing fetched", async (value) => {
    const result = await runCli({ AAB_PATH: value });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.out.join("\n")).toMatch(/AAB_PATH/);
  });

  it("AAB_PATH pointing at a file that does not exist: refused, nothing fetched", async () => {
    const result = await runCli({ AAB_PATH: join(workDir, "missing.aab") });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.out.join("\n")).toMatch(/AAB_PATH/);
  });

  it("AAB_PATH pointing at a directory: refused, nothing fetched", async () => {
    const dir = join(workDir, "a-directory");
    mkdirSync(dir, { recursive: true });
    const result = await runCli({ AAB_PATH: dir });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
  });

  it("AAB_PATH pointing at an empty file: refused, nothing fetched", async () => {
    const empty = join(workDir, "empty.aab");
    writeFileSync(empty, "");
    const result = await runCli({ AAB_PATH: empty });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.out.join("\n")).toMatch(/empty/i);
  });

  it.each(["true", "false", "", "yes"])(
    "DRY_RUN=%j is refused in this mode: there is no dry run here, and a flag that silently does nothing would lie",
    async (value) => {
      const result = await runCli({ DRY_RUN: value });
      expect(result.exitCode).toBe(1);
      expect(result.fetched).toEqual([]);
      expect(result.out.join("\n")).toMatch(/DRY_RUN/);
    },
  );

  it.each(["upload_internal", "UPLOAD-INTERNAL", "", " upload-internal", "promote", "upload-internal "])(
    "PLAY_RELEASE_MODE=%j is rejected (fail closed, no guessing)",
    async (value) => {
      const result = await runCli({ PLAY_RELEASE_MODE: value, DRY_RUN: "true", RELEASE_NOTES: "Bug fixes." });
      expect(result.exitCode).toBe(1);
      expect(result.fetched).toEqual([]);
      expect(result.out.join("\n")).toMatch(/PLAY_RELEASE_MODE/);
      expect(result.summary).toMatch(/Failed/);
    },
  );

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

  it("a key file whose token_uri is not Google's is rejected before any network call, without echoing it", async () => {
    const doctored = JSON.stringify({ ...JSON.parse(saJson), token_uri: "https://evil.example/collect" });
    const result = await runCli({ PLAY_SERVICE_ACCOUNT_JSON: doctored });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    const all = [...result.out, result.summary ?? ""].join("\n");
    expect(all).toMatch(/token_uri/);
    expect(all).not.toContain("evil.example");
  });
});

describe("run() upload-internal — credentials: masked, pinned, never printed", () => {
  it("masks the signed assertion first and the access token second, before anything else is logged", async () => {
    const result = await runCli();
    expect(result.masked).toEqual([ASSERTION(), TOKEN]);
  });

  it("without an injected hook, on GitHub Actions, masks go out as ::add-mask:: commands (assertion, then token), first of all", async () => {
    const result = await runCli({ GITHUB_ACTIONS: "true" }, {}, undefined, false);
    const masks = result.out.filter((line) => line.startsWith("::add-mask::"));
    expect(masks).toEqual([`::add-mask::${ASSERTION()}`, `::add-mask::${TOKEN}`]);
    expect(result.out.indexOf(masks[0]!)).toBeLessThan(result.out.findIndex((l) => !l.startsWith("::add-mask::")));
  });

  it.each([undefined, "", "false", "TRUE", "1"])(
    "without an injected hook and GITHUB_ACTIONS=%j (a local run), the signed assertion and the token are NOT printed",
    async (value) => {
      const result = await runCli({ GITHUB_ACTIONS: value }, {}, undefined, false);
      expect(result.exitCode).toBe(0);
      const all = result.out.join("\n");
      expect(all).not.toContain("::add-mask::");
      expect(all).not.toContain(ASSERTION());
      expect(all).not.toContain(TOKEN);
    },
  );

  it("the only hosts contacted are Google's token endpoint and the Play API; the bearer token goes only to the latter", async () => {
    const hosts = new Set<string>();
    const fake = createFakePlay(internalUploadRoutes());
    const auth: { url: string; authorization: string | undefined }[] = [];
    const fetchFn: FetchFn = async (url, init) => {
      hosts.add(new URL(url).host);
      auth.push({ url, authorization: (init?.headers as Record<string, string> | undefined)?.authorization });
      if (url === TOKEN_URI) return jsonResponse({ access_token: TOKEN })();
      return fake.fetchFn(url, init);
    };
    const exitCode = await run(
      { PLAY_SERVICE_ACCOUNT_JSON: saJson, PLAY_RELEASE_MODE: "upload-internal", AAB_PATH: aabPath },
      { fetchFn, now: () => 1_760_000_000_000, log: () => undefined, mask: () => undefined },
    );
    expect(exitCode).toBe(0);
    expect([...hosts].sort()).toEqual(["androidpublisher.googleapis.com", "oauth2.googleapis.com"]);
    for (const call of auth) {
      expect(call.authorization === `Bearer ${TOKEN}`).toBe(new URL(call.url).host === "androidpublisher.googleapis.com");
    }
  });

  it("no log line or summary contains the key, the assertion, the token, the raw JSON or the bundle", async () => {
    for (const overrides of [
      {},
      { AAB_PATH: undefined },
      { PLAY_RELEASE_MODE: "nope" },
    ] as Record<string, string | undefined>[]) {
      const plays: Record<string, Reply>[] = [{}, { [COMMIT]: changesAlreadyInReview() }, { [COMMIT]: playError(500, "boom", "INTERNAL") }];
      for (const play of plays) {
        const result = await runCli(overrides, play);
        const everything = [...result.out, result.summary ?? ""].join("\n");
        expect(everything).not.toContain(TOKEN);
        expect(everything).not.toContain(ASSERTION());
        expect(everything).not.toContain(saJson);
        expect(everything).not.toContain("PRIVATE KEY");
        expect(everything).not.toContain(privateKeyPem.split("\n")[1]!);
        expect(everything).not.toContain("assertion");
        expect(everything).not.toContain(AAB_MARKER);
      }
    }
  });

  it("no secret leaks when a Play call fails mid-flight", async () => {
    const result = await runCli({}, { [INTERNAL_PUT]: playError(403, "The caller does not have permission", "PERMISSION_DENIED") });
    const everything = [...result.out, result.summary ?? ""].join("\n");
    expect(everything).not.toContain(TOKEN);
    expect(everything).not.toContain("PRIVATE KEY");
  });
});

describe("run() — release mode is untouched by the new mode", () => {
  const releaseEnv = { RELEASE_NOTES: "Bug fixes and a faster map.", DRY_RUN: "true" };

  it.each([undefined, "release"])(
    "PLAY_RELEASE_MODE=%j: the original release flow, dry run — validates, never commits, never uploads",
    async (mode) => {
      const result = await runCli({ PLAY_RELEASE_MODE: mode, AAB_PATH: undefined, ...releaseEnv });
      expect(result.exitCode).toBe(0);
      expect(result.fetched.some((f) => f.includes(":validate"))).toBe(true);
      expect(result.fetched.some((f) => f.includes(":commit"))).toBe(false);
      expect(result.play.some((p) => p.includes("/upload/") || p.includes("/bundles"))).toBe(false);
      expect(result.summary).toMatch(/Dry run/);
    },
  );

  it("real release run: commits with ERROR_IF_IN_REVIEW only — changesNotSentForReview is never set", async () => {
    const result = await runCli({ PLAY_RELEASE_MODE: undefined, ...releaseEnv, DRY_RUN: "false" });
    expect(result.exitCode).toBe(0);
    const commits = result.fetched.filter((f) => f.includes(":commit"));
    expect(commits).toHaveLength(1);
    expect(commits[0]).toContain("changesInReviewBehavior=ERROR_IF_IN_REVIEW");
    expect(commits[0]).not.toContain("changesNotSentForReview");
  });

  it("a release-mode refusal that upload-internal would retry still FAILS in release mode (the tool never sets changesNotSentForReview there)", async () => {
    const result = await runCli(
      { PLAY_RELEASE_MODE: undefined, ...releaseEnv, DRY_RUN: "false" },
      { [COMMIT]: changesCannotBeSentAutomatically() },
    );
    expect(result.exitCode).toBe(1);
    expect(result.fetched.some((f) => f.includes("changesNotSentForReview"))).toBe(false);
    expect(annotations(result.out, "error")[0]).toContain("Send changes for review");
  });

  it("release mode still insists on DRY_RUN (fail closed) when AAB_PATH is present", async () => {
    const result = await runCli({ PLAY_RELEASE_MODE: undefined, RELEASE_NOTES: "Bug fixes.", DRY_RUN: undefined });
    expect(result.exitCode).toBe(1);
    expect(result.fetched).toEqual([]);
    expect(result.out.join("\n")).toMatch(/DRY_RUN/);
  });
});
