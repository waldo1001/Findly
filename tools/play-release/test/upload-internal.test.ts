import { describe, expect, it } from "vitest";
import { PlayApiError, PlayClient } from "../src/play-client";
import { uploadInternal } from "../src/upload-internal";
import {
  COMMIT,
  COMMIT_UNSENT,
  DELETE_EDIT,
  EDIT_ID,
  INTERNAL_PUT,
  TOKEN,
  UPLOAD,
  UPLOADED_VERSION_CODE,
  bundleResponse,
  changesAlreadyInReview,
  changesAreSentAutomatically,
  changesCannotBeSentAutomatically,
  createFakePlay,
  emptyResponse,
  internalUploadRoutes,
  jsonResponse,
  playError,
} from "./support/fake-play";
import type { Reply } from "./support/fake-play";

// The orchestration of one internal-track upload (docs/store-readiness.md §5, "Android internal-track
// upload (A59)"): which Play calls are made, in which order, and the safety properties — the commit
// never takes Play's cancel-the-review default, a change already in review defers (never cancels),
// the one retry carries changesNotSentForReview AND ERROR_IF_IN_REVIEW, and every edit that is not
// committed is deleted. Verified against a stub `fetch` only; nothing here has touched the real Play API.

const BUNDLE = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0xde, 0xad, 0xbe, 0xef]);
const OPEN = ["POST /edits", UPLOAD, INTERNAL_PUT];

function setup(overrides: Record<string, Reply> = {}) {
  const fake = createFakePlay({ ...internalUploadRoutes(), ...overrides });
  const api = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android");
  const log: string[] = [];
  const run = () => uploadInternal({ api, bundle: BUNDLE, log: (line) => log.push(line) });
  return { fake, run, log };
}

describe("uploadInternal() — committed", () => {
  it("makes exactly: insert edit, upload the bundle, set the internal track, commit — and deletes nothing", async () => {
    const { fake, run } = setup();
    const outcome = await run();
    expect(fake.sequence()).toEqual([...OPEN, COMMIT]);
    expect(outcome).toEqual({ kind: "committed", versionCode: UPLOADED_VERSION_CODE, notSentForReview: false });
  });

  it("sets the INTERNAL track to exactly the uploaded version code, completed — and touches no other track", async () => {
    const { fake, run } = setup();
    await run();
    const puts = fake.calls.filter((c) => c.method === "PUT");
    expect(puts).toHaveLength(1);
    expect(puts[0]!.path).toBe(`/edits/${EDIT_ID}/tracks/internal`);
    expect(puts[0]!.body).toEqual({ track: "internal", releases: [{ versionCodes: ["235"], status: "completed" }] });
    expect(fake.calls.some((c) => /tracks\/(production|alpha|beta)/.test(c.path))).toBe(false);
  });

  it("uses the version code Play reports for the upload, whatever it is (as a string, the way the track API wants it)", async () => {
    const { fake, run } = setup({ [UPLOAD]: bundleResponse(4711) });
    const outcome = await run();
    expect(fake.calls.find((c) => c.method === "PUT")!.body).toEqual({
      track: "internal",
      releases: [{ versionCodes: ["4711"], status: "completed" }],
    });
    expect(outcome).toMatchObject({ kind: "committed", versionCode: 4711 });
  });

  it("uploads the bundle bytes it was given", async () => {
    const { fake, run } = setup();
    await run();
    expect(Array.from(fake.calls[1]!.bytes ?? [])).toEqual(Array.from(BUNDLE));
  });

  it("the first commit carries ERROR_IF_IN_REVIEW and never changesNotSentForReview — Play's cancelling default is unreachable", async () => {
    const { fake, run } = setup();
    await run();
    const commits = fake.calls.filter((c) => c.path.includes(":commit"));
    expect(commits).toHaveLength(1);
    expect(commits[0]!.url).toBe(
      "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.findly.android/edits/EDIT123:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW",
    );
  });

  it("does not validate separately (the commit validates) and never lists or reads production", async () => {
    const { fake, run } = setup();
    await run();
    expect(fake.calls.some((c) => c.path.includes(":validate"))).toBe(false);
    expect(fake.calls.some((c) => c.method === "GET")).toBe(false);
  });
});

describe("uploadInternal() — production review in progress: deferred, never cancelled", () => {
  it("CHANGES_ALREADY_IN_REVIEW: one commit, then the edit is deleted — and the outcome is 'deferred', not a failure", async () => {
    const { fake, run, log } = setup({ [COMMIT]: changesAlreadyInReview() });
    const outcome = await run();
    expect(fake.sequence()).toEqual([...OPEN, COMMIT, DELETE_EDIT]);
    expect(outcome).toEqual({ kind: "deferred", versionCode: UPLOADED_VERSION_CODE });
    expect(log.join("\n")).toMatch(/in review/i);
  });

  it("never retries with changesNotSentForReview, and never commits without ERROR_IF_IN_REVIEW", async () => {
    const { fake, run } = setup({ [COMMIT]: changesAlreadyInReview() });
    await run();
    expect(fake.calls.filter((c) => c.path.includes(":commit"))).toHaveLength(1);
    expect(fake.calls.some((c) => c.url.includes("changesNotSentForReview"))).toBe(false);
  });

  it("a failing delete only warns: the run is still 'deferred'", async () => {
    const { run, log } = setup({
      [COMMIT]: changesAlreadyInReview(),
      [DELETE_EDIT]: playError(500, "oops", "INTERNAL"),
    });
    const outcome = await run();
    expect(outcome.kind).toBe("deferred");
    expect(log.some((l) => /could not delete/i.test(l))).toBe(true);
  });
});

describe("uploadInternal() — Play wants changesNotSentForReview: one retry, with ERROR_IF_IN_REVIEW kept", () => {
  it.each([
    ["Changes cannot be sent for review automatically."],
    ["Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true."],
  ])("refusal %j, then the retry commits: exactly two commits, the edit is kept", async (message) => {
    const { fake, run } = setup({ [COMMIT]: changesCannotBeSentAutomatically(message), [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
    const outcome = await run();
    expect(fake.sequence()).toEqual([...OPEN, COMMIT, COMMIT_UNSENT]);
    expect(outcome).toEqual({ kind: "committed", versionCode: UPLOADED_VERSION_CODE, notSentForReview: true });
  });

  it("the retry's query string is exactly changesInReviewBehavior=ERROR_IF_IN_REVIEW&changesNotSentForReview=true", async () => {
    const { fake, run } = setup({ [COMMIT]: changesCannotBeSentAutomatically(), [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
    await run();
    const commits = fake.calls.filter((c) => c.path.includes(":commit")).map((c) => c.url.split("?")[1]);
    expect(commits).toEqual([
      "changesInReviewBehavior=ERROR_IF_IN_REVIEW",
      "changesInReviewBehavior=ERROR_IF_IN_REVIEW&changesNotSentForReview=true",
    ]);
  });

  it("retry then fails: the run fails with Play's message, the edit is deleted, and there is no second retry", async () => {
    const { fake, run } = setup({
      [COMMIT]: changesCannotBeSentAutomatically(),
      [COMMIT_UNSENT]: playError(400, "Version code 235 is invalid."),
    });
    await expect(run()).rejects.toThrow(/Version code 235 is invalid/);
    expect(fake.sequence()).toEqual([...OPEN, COMMIT, COMMIT_UNSENT, DELETE_EDIT]);
  });

  it("retry refused again for the same reason: that is a failure, not an endless loop (one retry only)", async () => {
    const { fake, run } = setup({
      [COMMIT]: changesCannotBeSentAutomatically(),
      [COMMIT_UNSENT]: changesCannotBeSentAutomatically(),
    });
    await expect(run()).rejects.toThrow(/cannot be sent for review automatically/i);
    expect(fake.calls.filter((c) => c.path.includes(":commit"))).toHaveLength(2);
    expect(fake.calls.at(-1)!.method).toBe("DELETE");
  });

  it("the retry hits 'changes already in review': deferred, edit deleted, still nothing cancelled", async () => {
    const { fake, run } = setup({
      [COMMIT]: changesCannotBeSentAutomatically(),
      [COMMIT_UNSENT]: changesAlreadyInReview(),
    });
    const outcome = await run();
    expect(fake.sequence()).toEqual([...OPEN, COMMIT, COMMIT_UNSENT, DELETE_EDIT]);
    expect(outcome).toEqual({ kind: "deferred", versionCode: UPLOADED_VERSION_CODE });
  });

  it("logs that it is retrying, in one line each", async () => {
    const { run, log } = setup({ [COMMIT]: changesCannotBeSentAutomatically(), [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
    await run();
    expect(log.some((l) => /retry/i.test(l) && /changesNotSentForReview/.test(l))).toBe(true);
  });
});

describe("uploadInternal() — every other failure fails the run and deletes the edit", () => {
  it("the opposite refusal ('must not be set') is NOT retried with the flag — it fails", async () => {
    const { fake, run } = setup({ [COMMIT]: changesAreSentAutomatically() });
    await expect(run()).rejects.toThrow(/must not be set/);
    expect(fake.sequence()).toEqual([...OPEN, COMMIT, DELETE_EDIT]);
    expect(fake.calls.some((c) => c.url.includes("changesNotSentForReview"))).toBe(false);
  });

  it.each([
    ["an unrelated 400", playError(400, "Version code 235 has already been used.")],
    ["a 403", playError(403, "The caller does not have permission", "PERMISSION_DENIED")],
    ["a 500", playError(500, "Backend error", "INTERNAL")],
  ])("%s on the commit: the run fails with Play's message, no retry, edit deleted", async (_label, reply) => {
    const { fake, run } = setup({ [COMMIT]: reply });
    const failure = run();
    await expect(failure).rejects.toBeInstanceOf(PlayApiError);
    expect(fake.sequence()).toEqual([...OPEN, COMMIT, DELETE_EDIT]);
  });

  it("the upload fails: nothing is set or committed, the edit is deleted, Play's message surfaces", async () => {
    const { fake, run } = setup({ [UPLOAD]: playError(400, "Version code 235 has already been used.") });
    await expect(run()).rejects.toThrow(/Version code 235 has already been used/);
    expect(fake.sequence()).toEqual(["POST /edits", UPLOAD, DELETE_EDIT]);
  });

  it("the upload answers without a usable version code: fails before touching the track", async () => {
    const { fake, run } = setup({ [UPLOAD]: emptyResponse(200) });
    await expect(run()).rejects.toThrow(/version code/i);
    expect(fake.sequence()).toEqual(["POST /edits", UPLOAD, DELETE_EDIT]);
  });

  it("setting the track fails: no commit, the edit is deleted, Play's message surfaces", async () => {
    const { fake, run } = setup({ [INTERNAL_PUT]: playError(400, "Version code 235 is not allowed on this track.") });
    await expect(run()).rejects.toThrow(/not allowed on this track/);
    expect(fake.sequence()).toEqual([...OPEN, DELETE_EDIT]);
  });

  it("the edit cannot even be opened: the run fails and there is nothing to delete", async () => {
    const { fake, run } = setup({ "POST /edits": playError(403, "The caller does not have permission", "PERMISSION_DENIED") });
    await expect(run()).rejects.toThrow(/403/);
    expect(fake.sequence()).toEqual(["POST /edits"]);
  });

  it("a failing cleanup never replaces the original error", async () => {
    const { run, log } = setup({
      [COMMIT]: playError(400, "Version code 235 has already been used."),
      [DELETE_EDIT]: playError(500, "cleanup boom", "INTERNAL"),
    });
    await expect(run()).rejects.toThrow(/already been used/);
    expect(log.some((l) => /could not delete/i.test(l))).toBe(true);
  });
});

describe("uploadInternal() — log hygiene", () => {
  it("every log line is a single line, even when Play's message tries to start a workflow command", async () => {
    const { run, log } = setup({
      [COMMIT]: changesAlreadyInReview(),
      [DELETE_EDIT]: playError(500, "oops\n::add-mask::everything", "INTERNAL"),
    });
    await run();
    expect(log.every((l) => !/[\r\n]/.test(l))).toBe(true);
    expect(log.filter((l) => l.startsWith("::"))).toEqual([]);
  });

  it("never logs the token or the bundle bytes", async () => {
    const { run, log } = setup({ [COMMIT]: changesCannotBeSentAutomatically(), [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
    await run();
    const everything = log.join("\n");
    expect(everything).not.toContain(TOKEN);
    expect(everything).not.toContain(Buffer.from(BUNDLE).toString("latin1"));
    expect(everything).not.toContain(Buffer.from(BUNDLE).toString("base64"));
  });

  it("names the version code it uploaded", async () => {
    const { run, log } = setup();
    await run();
    expect(log.join("\n")).toContain(String(UPLOADED_VERSION_CODE));
  });
});
