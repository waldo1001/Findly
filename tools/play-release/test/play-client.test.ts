import { describe, expect, it } from "vitest";
import { PlayApiError, PlayClient } from "../src/play-client";
import type { TrackBody } from "../src/plan";
import internalCompleted from "./fixtures/internal-completed.json";
import listings from "./fixtures/listings.json";
import {
  BASE,
  COMMIT,
  EDIT_ID,
  PRODUCTION_RELEASES,
  TOKEN,
  changesAlreadyInReview,
  createFakePlay,
  emptyResponse,
  jsonResponse,
  playError,
  releaseSummaries,
  releaseSummary,
} from "./support/fake-play";

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
