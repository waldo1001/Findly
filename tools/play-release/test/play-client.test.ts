import { afterEach, describe, expect, it, vi } from "vitest";
import { PlayApiError, PlayClient, requiresChangesNotSentForReview } from "../src/play-client";
import type { TrackBody } from "../src/plan";
import internalCompleted from "./fixtures/internal-completed.json";
import listings from "./fixtures/listings.json";
import {
  BASE,
  COMMIT,
  COMMIT_UNSENT,
  EDIT_ID,
  INTERNAL_PUT,
  PRODUCTION_RELEASES,
  TOKEN,
  UPLOAD,
  UPLOADED_VERSION_CODE,
  UPLOAD_BASE,
  bundleResponse,
  changesAlreadyInReview,
  changesAreSentAutomatically,
  changesCannotBeSentAutomatically,
  createFakePlay,
  emptyResponse,
  internalUploadRoutes,
  jsonResponse,
  playError,
  releaseSummaries,
  releaseSummary,
} from "./support/fake-play";
import type { Reply } from "./support/fake-play";

// The thin HTTP layer: one method per Play Developer API v3 call the release flow needs. Everything
// here is verified against a stub `fetch` only — never against the real Play API.

function client(overrides = {}) {
  const fake = createFakePlay(overrides);
  return { fake, play: new PlayClient(fake.fetchFn, TOKEN, "com.findly.android") };
}

describe("PlayClient — requests", () => {
  it("insertEdit: POST /edits, returns the edit id", async () => {
    const { fake, play } = client();
    expect(await play.insertEdit()).toBe(EDIT_ID);
    expect(fake.calls).toHaveLength(1);
    expect(fake.calls[0]!.method).toBe("POST");
    expect(fake.calls[0]!.url).toBe(`${BASE}/edits`);
  });

  it("sends the bearer token on every request and never anywhere else", async () => {
    const { fake, play } = client();
    await play.insertEdit();
    await play.getTrack(EDIT_ID, "internal");
    await play.listListingLanguages(EDIT_ID);
    await play.validate(EDIT_ID);
    await play.deleteEdit(EDIT_ID);
    for (const call of fake.calls) {
      expect(call.headers.authorization).toBe(`Bearer ${TOKEN}`);
      expect(call.url).not.toContain(TOKEN);
    }
  });

  it("getTrack: GET /edits/{id}/tracks/{track}, returns the parsed track", async () => {
    const { fake, play } = client();
    expect(await play.getTrack(EDIT_ID, "internal")).toEqual(internalCompleted);
    expect(fake.sequence()).toEqual([`GET /edits/${EDIT_ID}/tracks/internal`]);
  });

  it("getTrack: a 404 means 'no such track' and returns undefined", async () => {
    const { play } = client({
      [`GET /edits/${EDIT_ID}/tracks/production`]: playError(404, "Track not found.", "NOT_FOUND"),
    });
    expect(await play.getTrack(EDIT_ID, "production")).toBeUndefined();
  });

  it("getTrack: any other error is raised, not swallowed", async () => {
    const { play } = client({
      [`GET /edits/${EDIT_ID}/tracks/production`]: playError(403, "The caller does not have permission", "PERMISSION_DENIED"),
    });
    await expect(play.getTrack(EDIT_ID, "production")).rejects.toThrow(/403.*does not have permission/);
  });

  it("listListingLanguages: GET /edits/{id}/listings, returns the language codes", async () => {
    const { fake, play } = client();
    expect(await play.listListingLanguages(EDIT_ID)).toEqual(listings.listings.map((l) => l.language));
    expect(fake.sequence()).toEqual([`GET /edits/${EDIT_ID}/listings`]);
  });

  it("listListingLanguages: a response without a listings key means none", async () => {
    const { play } = client({
      [`GET /edits/${EDIT_ID}/listings`]: jsonResponse({ kind: "androidpublisher#listingsListResponse" }),
    });
    expect(await play.listListingLanguages(EDIT_ID)).toEqual([]);
  });

  it("updateTrack: PUT /edits/{id}/tracks/{track} with the body as JSON", async () => {
    const { fake, play } = client();
    const body: TrackBody = {
      track: "production",
      releases: [{ versionCodes: ["234"], status: "completed", releaseNotes: [{ language: "en-GB", text: "Hi" }] }],
    };
    await play.updateTrack(EDIT_ID, body);
    const call = fake.calls[0]!;
    expect(call.method).toBe("PUT");
    expect(call.path).toBe(`/edits/${EDIT_ID}/tracks/production`);
    expect(call.headers["content-type"]).toBe("application/json");
    expect(call.body).toEqual(body);
  });

  it("validate: POST /edits/{id}:validate", async () => {
    const { fake, play } = client();
    await play.validate(EDIT_ID);
    expect(fake.sequence()).toEqual([`POST /edits/${EDIT_ID}:validate`]);
  });

  it("commit: POST /edits/{id}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW — never cancels a change in review", async () => {
    const { fake, play } = client();
    expect(await play.commit(EDIT_ID)).toBe("committed");
    expect(fake.sequence()).toEqual([COMMIT]);
    expect(fake.calls[0]!.url).toBe(`${BASE}/edits/${EDIT_ID}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW`);
  });

  it("commit: never sets changesNotSentForReview (an edit must go to review, not sit unsent)", async () => {
    const { fake, play } = client();
    await play.commit(EDIT_ID);
    expect(fake.calls[0]!.url).not.toContain("changesNotSentForReview");
  });

  it("commit: a 400 with reason CHANGES_ALREADY_IN_REVIEW is reported as 'changes-in-review', not thrown", async () => {
    const { play } = client({ [COMMIT]: changesAlreadyInReview() });
    expect(await play.commit(EDIT_ID)).toBe("changes-in-review");
  });

  it("commit: the reason is also recognised in the legacy errors[] list, in any casing", async () => {
    const legacy = jsonResponse(
      { error: { code: 400, message: "in review", errors: [{ reason: "changesAlreadyInReview", domain: "global" }] } },
      400,
    );
    const { play } = client({ [COMMIT]: legacy });
    expect(await play.commit(EDIT_ID)).toBe("changes-in-review");
  });

  it("commit: a 400 WITHOUT that reason is an error (e.g. 'cannot be sent for review automatically')", async () => {
    const reason = "Changes cannot be sent for review automatically.";
    const { play } = client({ [COMMIT]: playError(400, reason) });
    await expect(play.commit(EDIT_ID)).rejects.toThrow(reason);
  });

  it("commit: the reason only counts on a 400 — the same reason on a 500 is still an error", async () => {
    const odd = jsonResponse({ error: { code: 500, message: "boom", details: [{ reason: "CHANGES_ALREADY_IN_REVIEW" }] } }, 500);
    const { play } = client({ [COMMIT]: odd });
    await expect(play.commit(EDIT_ID)).rejects.toThrow(/500/);
  });

  it("commit: a 404 is an error everywhere except tracks.get", async () => {
    const { play } = client({ [COMMIT]: playError(404, "Edit not found.", "NOT_FOUND") });
    await expect(play.commit(EDIT_ID)).rejects.toThrow(/404.*Edit not found/);
  });

  it("a dry-run client refuses to commit — structurally, without sending any request", async () => {
    const fake = createFakePlay();
    const play = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android", { dryRun: true });
    await expect(play.commit(EDIT_ID)).rejects.toThrow(/dry run/i);
    expect(fake.calls).toHaveLength(0);
  });

  it("a dry-run client still does everything else (reads, updates, validates, deletes)", async () => {
    const fake = createFakePlay();
    const play = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android", { dryRun: true });
    await play.insertEdit();
    await play.getTrack(EDIT_ID, "internal");
    await play.updateTrack(EDIT_ID, { track: "production", releases: [] });
    await play.validate(EDIT_ID);
    await play.deleteEdit(EDIT_ID);
    expect(fake.calls).toHaveLength(5);
  });

  it("listReleases: GET /tracks/{track}/releases — read-only, outside any edit", async () => {
    const { fake, play } = client();
    await play.listReleases("production");
    expect(fake.sequence()).toEqual([PRODUCTION_RELEASES]);
    expect(fake.calls[0]!.url).toBe(`${BASE}/tracks/production/releases`);
  });

  // Google's Discovery document (androidpublisher v3), schema ReleaseSummary: releaseName, track,
  // activeArtifacts[] { versionCode: int32 } and releaseLifecycleState — and nothing else.
  it("listReleases: parses a response in Google's documented ReleaseSummary shape (activeArtifacts[].versionCode)", async () => {
    const { play } = client();
    expect(await play.listReleases("production")).toEqual([
      {
        releaseName: "1.2.0 (234)",
        track: "production",
        activeArtifacts: [{ versionCode: 234 }],
        releaseLifecycleState: "RELEASE_LIFECYCLE_STATE_IN_REVIEW",
      },
    ]);
  });

  it("listReleases: several artifacts and several releases come through, in order", async () => {
    const { play } = client({
      [PRODUCTION_RELEASES]: releaseSummaries(
        releaseSummary("1.2.0 (234)", [233, 234], "IN_REVIEW"),
        releaseSummary("1.1.0 (230)", [230], "PUBLISHED"),
      ),
    });
    const releases = await play.listReleases("production");
    expect(releases.map((r) => r.releaseName)).toEqual(["1.2.0 (234)", "1.1.0 (230)"]);
    expect(releases[0]!.activeArtifacts).toEqual([{ versionCode: 233 }, { versionCode: 234 }]);
    expect(releases[1]!.releaseLifecycleState).toBe("RELEASE_LIFECYCLE_STATE_PUBLISHED");
  });

  it("listReleases: a release without artifacts, and artifacts without a usable versionCode, yield no codes", async () => {
    const { play } = client({
      [PRODUCTION_RELEASES]: jsonResponse({
        releases: [
          { releaseName: "draft", releaseLifecycleState: "RELEASE_LIFECYCLE_STATE_DRAFT" },
          { releaseName: "odd", activeArtifacts: [{}, { versionCode: "234" }, { versionCode: 1.5 }, "x", null, { versionCode: 7 }] },
        ],
      }),
    });
    const [draft, odd] = await play.listReleases("production");
    expect(draft!.activeArtifacts ?? []).toEqual([]);
    expect(odd!.activeArtifacts).toEqual([{ versionCode: 7 }]);
  });

  it("listReleases: fields that are not part of ReleaseSummary are not read (no status, no lastUpdateTime, no versionCodes)", async () => {
    const { play } = client({
      [PRODUCTION_RELEASES]: jsonResponse({
        releases: [{ releaseName: "x", versionCodes: ["234"], status: "completed", lastUpdateTime: "2026-10-05T10:00:00Z" }],
      }),
    });
    expect(await play.listReleases("production")).toEqual([{ releaseName: "x" }]);
  });

  it("listReleases: no releases key means none", async () => {
    const { play } = client({ [PRODUCTION_RELEASES]: jsonResponse({}) });
    expect(await play.listReleases("production")).toEqual([]);
  });

  it("listReleases: errors are raised (the caller decides that it is best-effort)", async () => {
    const { play } = client({ [PRODUCTION_RELEASES]: playError(403, "The caller does not have permission", "PERMISSION_DENIED") });
    await expect(play.listReleases("production")).rejects.toThrow(/403/);
  });

  it("404 is an error for updateTrack and validate too — only getTrack reads it as 'no such track'", async () => {
    const { play } = client({
      [`PUT /edits/${EDIT_ID}/tracks/production`]: playError(404, "Edit not found.", "NOT_FOUND"),
      [`POST /edits/${EDIT_ID}:validate`]: playError(404, "Edit not found.", "NOT_FOUND"),
      [`GET /edits/${EDIT_ID}/listings`]: playError(404, "Edit not found.", "NOT_FOUND"),
      [`DELETE /edits/${EDIT_ID}`]: playError(404, "Edit not found.", "NOT_FOUND"),
      "POST /edits": playError(404, "Application not found.", "NOT_FOUND"),
    });
    await expect(play.updateTrack(EDIT_ID, { track: "production", releases: [] })).rejects.toThrow(/PUT.*404/);
    await expect(play.validate(EDIT_ID)).rejects.toThrow(/validate.*404/);
    await expect(play.listListingLanguages(EDIT_ID)).rejects.toThrow(/404/);
    await expect(play.deleteEdit(EDIT_ID)).rejects.toThrow(/DELETE.*404/);
    await expect(play.insertEdit()).rejects.toThrow(/404.*Application not found/);
  });

  it("deleteEdit: DELETE /edits/{id}, tolerates the empty 204 body", async () => {
    const { fake, play } = client();
    await play.deleteEdit(EDIT_ID);
    expect(fake.sequence()).toEqual([`DELETE /edits/${EDIT_ID}`]);
  });

  it("url-encodes the edit id and track name", async () => {
    const { fake, play } = client({ "GET /edits/a%2Fb/tracks/we%20ird": jsonResponse({ track: "x" }) });
    await play.getTrack("a/b", "we ird");
    expect(fake.calls[0]!.path).toBe("/edits/a%2Fb/tracks/we%20ird");
  });
});

describe("PlayClient — errors", () => {
  it("surfaces Play's own message and the HTTP status, e.g. for a commit refused for review state", async () => {
    const reason = "Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true.";
    const { play } = client({ [COMMIT]: playError(400, reason) });
    const failure = play.commit(EDIT_ID);
    await expect(failure).rejects.toThrow(reason);
    await expect(failure).rejects.toThrow(/400/);
    await expect(failure).rejects.toBeInstanceOf(PlayApiError);
  });

  it("names the failing call", async () => {
    const { play } = client({ [`POST /edits/${EDIT_ID}:validate`]: playError(400, "Version code 234 is invalid.") });
    await expect(play.validate(EDIT_ID)).rejects.toThrow(/POST .*:validate/);
  });

  it("exposes the HTTP status on the error", async () => {
    const { play } = client({ "POST /edits": playError(401, "Invalid Credentials", "UNAUTHENTICATED") });
    const error = await play.insertEdit().catch((e: unknown) => e);
    expect(error).toBeInstanceOf(PlayApiError);
    expect((error as PlayApiError).status).toBe(401);
  });

  it("copes with a non-JSON error body, without echoing it", async () => {
    const { play } = client({
      [COMMIT]: () => new Response("<html>upstream sensitive-marker</html>", { status: 503 }),
    });
    const failure = play.commit(EDIT_ID);
    await expect(failure).rejects.toThrow(/503/);
    await failure.catch((e: Error) => expect(e.message).not.toContain("sensitive-marker"));
  });

  it("a network failure is reported without leaking the bearer token", async () => {
    const play = new PlayClient(
      async (_url, init) => {
        throw new Error(`connect ECONNRESET with ${JSON.stringify(init?.headers)}`);
      },
      TOKEN,
      "com.findly.android",
    );
    const failure = play.insertEdit();
    await expect(failure).rejects.toThrow(/network error/i);
    await failure.catch((e: Error) => expect(e.message).not.toContain(TOKEN));
  });

  it("insertEdit fails clearly when Play returns no edit id", async () => {
    const { play } = client({ "POST /edits": jsonResponse({}) });
    await expect(play.insertEdit()).rejects.toThrow(/edit id/i);
  });

  it("an empty 200 body on a call that needs JSON is an error, not a crash", async () => {
    const { play } = client({ [`GET /edits/${EDIT_ID}/tracks/internal`]: emptyResponse(200) });
    await expect(play.getTrack(EDIT_ID, "internal")).rejects.toThrow(/track/i);
  });

  it("passes an abort signal so a hung request cannot stall the job forever", async () => {
    let signal: AbortSignal | null | undefined;
    const play = new PlayClient(
      async (_url, init) => {
        signal = init?.signal;
        return jsonResponse({ id: EDIT_ID })();
      },
      TOKEN,
      "com.findly.android",
    );
    await play.insertEdit();
    expect(signal).toBeInstanceOf(AbortSignal);
  });
});

// --- A59: the internal-track upload (docs/store-readiness.md §5, "Android internal-track upload") ---
// Verified against a stub `fetch` only; the request shapes follow Google's Discovery document
// (androidpublisher v3, method edits.bundles.upload: simple media upload at
// /upload/androidpublisher/v3/applications/{packageName}/edits/{editId}/bundles, accepts
// application/octet-stream, returns a Bundle { versionCode: int32, sha1, sha256 }).

const BUNDLE = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0xde, 0xad, 0xbe, 0xef]);

function uploadClient(overrides = {}) {
  const fake = createFakePlay({ ...internalUploadRoutes(), ...overrides });
  return { fake, play: new PlayClient(fake.fetchFn, TOKEN, "com.findly.android") };
}

describe("PlayClient.uploadBundle — edits.bundles.upload", () => {
  it("POSTs the bytes to the media-upload endpoint with uploadType=media, exactly", async () => {
    const { fake, play } = uploadClient();
    await play.uploadBundle(EDIT_ID, BUNDLE);
    expect(fake.sequence()).toEqual([UPLOAD]);
    expect(fake.calls[0]!.url).toBe(
      "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/com.findly.android/edits/EDIT123/bundles?uploadType=media",
    );
    expect(fake.calls[0]!.url.startsWith(UPLOAD_BASE)).toBe(true);
  });

  it("sends the file as application/octet-stream, byte for byte, with the bearer token", async () => {
    const { fake, play } = uploadClient();
    await play.uploadBundle(EDIT_ID, BUNDLE);
    const call = fake.calls[0]!;
    expect(call.headers["content-type"]).toBe("application/octet-stream");
    expect(call.headers.authorization).toBe(`Bearer ${TOKEN}`);
    expect(call.url).not.toContain(TOKEN);
    expect(Array.from(call.bytes ?? [])).toEqual(Array.from(BUNDLE));
    expect(call.body).toBeUndefined();
  });

  it("returns the version code Play read from the bundle (Bundle.versionCode, an int32 JSON number)", async () => {
    const { play } = uploadClient();
    expect(await play.uploadBundle(EDIT_ID, BUNDLE)).toBe(UPLOADED_VERSION_CODE);
  });

  it.each([undefined, null, "235", 0, -1, 1.5, "abc"])("a response whose versionCode is %j is an error, not a guess", async (value) => {
    const { play } = uploadClient({ [UPLOAD]: bundleResponse(value) });
    await expect(play.uploadBundle(EDIT_ID, BUNDLE)).rejects.toThrow(/version code/i);
  });

  it("an empty or non-JSON 200 body is an error, not a crash", async () => {
    const empty = uploadClient({ [UPLOAD]: emptyResponse(200) });
    await expect(empty.play.uploadBundle(EDIT_ID, BUNDLE)).rejects.toThrow(/version code/i);
    const html = uploadClient({ [UPLOAD]: () => new Response("<html>sensitive-marker</html>", { status: 200 }) });
    const failure = html.play.uploadBundle(EDIT_ID, BUNDLE);
    await expect(failure).rejects.toThrow(/version code/i);
    await failure.catch((e: Error) => expect(e.message).not.toContain("sensitive-marker"));
  });

  it("surfaces Play's own message, the HTTP status and the call — never the token or the bytes", async () => {
    const { play } = uploadClient({ [UPLOAD]: playError(400, "Version code 235 has already been used.") });
    const failure = play.uploadBundle(EDIT_ID, BUNDLE);
    await expect(failure).rejects.toBeInstanceOf(PlayApiError);
    await expect(failure).rejects.toThrow(/POST .*\/bundles failed \(HTTP 400\): Version code 235 has already been used\./);
    await failure.catch((e: Error) => {
      expect(e.message).not.toContain(TOKEN);
      expect(e.message).not.toContain("uploadType");
    });
  });

  it("a 404 on the upload is an error too", async () => {
    const { play } = uploadClient({ [UPLOAD]: playError(404, "Edit not found.", "NOT_FOUND") });
    await expect(play.uploadBundle(EDIT_ID, BUNDLE)).rejects.toThrow(/404.*Edit not found/);
  });

  it("a network failure is reported without leaking the bearer token", async () => {
    const play = new PlayClient(
      async (_url, init) => {
        throw new Error(`connect ECONNRESET with ${JSON.stringify(init?.headers)}`);
      },
      TOKEN,
      "com.findly.android",
    );
    const failure = play.uploadBundle(EDIT_ID, BUNDLE);
    await expect(failure).rejects.toThrow(/network error/i);
    await failure.catch((e: Error) => expect(e.message).not.toContain(TOKEN));
  });

  it("passes an abort signal, so a hung upload cannot stall the job forever", async () => {
    const { fake, play } = uploadClient();
    await play.uploadBundle(EDIT_ID, BUNDLE);
    expect(fake.calls[0]!.signal).toBeInstanceOf(AbortSignal);
  });

  // A59 review round 1: "a signal is passed" would still pass if the upload silently fell back to the
  // 60 s limit of the JSON calls. `AbortSignal.timeout` exposes no duration, so the call is spied on.
  describe("timeouts", () => {
    afterEach(() => {
      vi.restoreAllMocks();
    });

    it("the bundle upload gets 300 s (Google recommends generous timeouts for edits.bundles.upload), not the 60 s of the JSON calls", async () => {
      const timeout = vi.spyOn(AbortSignal, "timeout");
      const { fake, play } = uploadClient();
      await play.uploadBundle(EDIT_ID, BUNDLE);
      expect(fake.calls).toHaveLength(1);
      expect(timeout).toHaveBeenCalledTimes(1);
      expect(timeout).toHaveBeenCalledWith(300_000);
    });

    it("every other call keeps the 60 s limit", async () => {
      const timeout = vi.spyOn(AbortSignal, "timeout");
      const { fake, play } = uploadClient({ [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
      await play.insertEdit();
      await play.getTrack(EDIT_ID, "internal");
      await play.listListingLanguages(EDIT_ID);
      await play.updateTrack(EDIT_ID, { track: "internal", releases: [{ versionCodes: ["235"], status: "completed" }] });
      await play.validate(EDIT_ID);
      await play.commit(EDIT_ID);
      await play.commit(EDIT_ID, { changesNotSentForReview: true });
      await play.deleteEdit(EDIT_ID);
      await play.listReleases("production");
      expect(fake.calls).toHaveLength(9);
      expect(timeout).toHaveBeenCalledTimes(9);
      for (const call of timeout.mock.calls) expect(call).toEqual([60_000]);
    });
  });

  it("a dry-run client refuses to upload — structurally, without sending any request", async () => {
    const fake = createFakePlay(internalUploadRoutes());
    const play = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android", { dryRun: true });
    await expect(play.uploadBundle(EDIT_ID, BUNDLE)).rejects.toThrow(/dry run/i);
    expect(fake.calls).toHaveLength(0);
  });

  it("the JSON calls are unchanged: still application/json, still the regular API root", async () => {
    const { fake, play } = uploadClient();
    await play.updateTrack(EDIT_ID, { track: "internal", releases: [{ versionCodes: ["235"], status: "completed" }] });
    expect(fake.calls[0]!.url).toBe(`${BASE}/edits/${EDIT_ID}/tracks/internal`);
    expect(fake.calls[0]!.headers["content-type"]).toBe("application/json");
  });
});

describe("PlayClient.updateTrack — a release without notes (the internal track)", () => {
  it("PUTs exactly {track, releases:[{versionCodes, status}]} — no releaseNotes key, nothing else", async () => {
    const { fake, play } = uploadClient();
    await play.updateTrack(EDIT_ID, { track: "internal", releases: [{ versionCodes: ["235"], status: "completed" }] });
    expect(fake.sequence()).toEqual([INTERNAL_PUT]);
    expect(fake.calls[0]!.body).toEqual({ track: "internal", releases: [{ versionCodes: ["235"], status: "completed" }] });
  });
});

describe("PlayClient.commit — the optional changesNotSentForReview (upload-internal's one retry)", () => {
  it("with changesNotSentForReview: POST …:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW&changesNotSentForReview=true, exactly", async () => {
    const { fake, play } = client({ [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
    expect(await play.commit(EDIT_ID, { changesNotSentForReview: true })).toBe("committed");
    expect(fake.sequence()).toEqual([COMMIT_UNSENT]);
    expect(fake.calls[0]!.url).toBe(
      `${BASE}/edits/${EDIT_ID}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW&changesNotSentForReview=true`,
    );
  });

  it("ERROR_IF_IN_REVIEW is never dropped, flag or no flag — the cancelling default must stay unreachable", async () => {
    const { fake, play } = client({ [COMMIT_UNSENT]: jsonResponse({ id: EDIT_ID }) });
    await play.commit(EDIT_ID);
    await play.commit(EDIT_ID, {});
    await play.commit(EDIT_ID, { changesNotSentForReview: false });
    await play.commit(EDIT_ID, { changesNotSentForReview: true });
    expect(fake.calls).toHaveLength(4);
    for (const call of fake.calls) expect(call.url).toContain("changesInReviewBehavior=ERROR_IF_IN_REVIEW");
    for (const call of fake.calls.slice(0, 3)) expect(call.url).not.toContain("changesNotSentForReview");
  });

  it("CHANGES_ALREADY_IN_REVIEW is still 'changes-in-review' on the retry commit", async () => {
    const { play } = client({ [COMMIT_UNSENT]: changesAlreadyInReview() });
    expect(await play.commit(EDIT_ID, { changesNotSentForReview: true })).toBe("changes-in-review");
  });

  it("any other refusal on the retry commit is an error", async () => {
    const { play } = client({ [COMMIT_UNSENT]: playError(400, "Version code 235 is invalid.") });
    await expect(play.commit(EDIT_ID, { changesNotSentForReview: true })).rejects.toThrow(/Version code 235 is invalid/);
  });

  it("a dry-run client refuses the retry commit as well", async () => {
    const fake = createFakePlay();
    const play = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android", { dryRun: true });
    await expect(play.commit(EDIT_ID, { changesNotSentForReview: true })).rejects.toThrow(/dry run/i);
    expect(fake.calls).toHaveLength(0);
  });
});

describe("requiresChangesNotSentForReview — Play's 'send this one unsent' refusal (the post-rejection state)", () => {
  const refusal = async (reply: Reply): Promise<unknown> => {
    const { play } = client({ [COMMIT]: reply });
    return play.commit(EDIT_ID).catch((e: unknown) => e);
  };

  it.each([
    ["the text observed on 2026-08-16", "Changes cannot be sent for review automatically."],
    ["with the instruction appended", "Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true."],
    ["in other casing", "CHANGES CANNOT BE SENT FOR REVIEW AUTOMATICALLY"],
    ["naming only the parameter", "Please set the query parameter changesNotSentForReview to true."],
  ])("recognises a 400 %s", async (_label, message) => {
    expect(requiresChangesNotSentForReview(await refusal(changesCannotBeSentAutomatically(message)))).toBe(true);
  });

  it("recognises it by a machine-readable reason too (details[] or legacy errors[], any casing)", async () => {
    const byDetail = jsonResponse(
      { error: { code: 400, message: "nope", details: [{ reason: "CHANGES_NOT_SENT_FOR_REVIEW_REQUIRED" }] } },
      400,
    );
    const byLegacy = jsonResponse({ error: { code: 400, message: "nope", errors: [{ reason: "changesNotSentForReview" }] } }, 400);
    expect(requiresChangesNotSentForReview(await refusal(byDetail))).toBe(true);
    expect(requiresChangesNotSentForReview(await refusal(byLegacy))).toBe(true);
  });

  it("does NOT match the opposite refusal ('must not be set') — retrying with the flag would be exactly wrong", async () => {
    expect(requiresChangesNotSentForReview(await refusal(changesAreSentAutomatically()))).toBe(false);
  });

  it.each([
    ["an unrelated 400", playError(400, "Version code 235 has already been used.")],
    ["a 400 without any message", jsonResponse({}, 400)],
    ["a 403", playError(403, "Changes cannot be sent for review automatically.", "PERMISSION_DENIED")],
    ["a 409", playError(409, "Changes cannot be sent for review automatically.", "ABORTED")],
    ["a 500", playError(500, "Changes cannot be sent for review automatically.", "INTERNAL")],
  ])("does not match %s", async (_label, reply) => {
    const error = await refusal(reply);
    expect(error).toBeInstanceOf(PlayApiError);
    expect(requiresChangesNotSentForReview(error)).toBe(false);
  });

  it.each([undefined, null, "Changes cannot be sent for review automatically.", new Error("Changes cannot be sent for review automatically.")])(
    "anything that is not a PlayApiError never matches (%j)",
    (value) => {
      expect(requiresChangesNotSentForReview(value)).toBe(false);
    },
  );
});
