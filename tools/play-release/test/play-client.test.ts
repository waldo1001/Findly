import { describe, expect, it } from "vitest";
import { PlayApiError, PlayClient } from "../src/play-client";
import type { TrackBody } from "../src/plan";
import internalCompleted from "./fixtures/internal-completed.json";
import listings from "./fixtures/listings.json";
import {
  BASE,
  EDIT_ID,
  TOKEN,
  createFakePlay,
  emptyResponse,
  jsonResponse,
  playError,
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

  it("commit: POST /edits/{id}:commit — no changesNotSentForReview, so the change goes to review", async () => {
    const { fake, play } = client();
    await play.commit(EDIT_ID);
    expect(fake.sequence()).toEqual([`POST /edits/${EDIT_ID}:commit`]);
    expect(fake.calls[0]!.url).not.toContain("changesNotSentForReview");
    expect(fake.calls[0]!.url).not.toContain("?");
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
    const { play } = client({ [`POST /edits/${EDIT_ID}:commit`]: playError(400, reason) });
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
      [`POST /edits/${EDIT_ID}:commit`]: () => new Response("<html>upstream sensitive-marker</html>", { status: 503 }),
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
