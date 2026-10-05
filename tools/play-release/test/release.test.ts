import { describe, expect, it } from "vitest";
import { PlayClient } from "../src/play-client";
import { release } from "../src/release";
import internalNoCompleted from "./fixtures/internal-no-completed.json";
import productionCurrent from "./fixtures/production-current.json";
import productionHalted from "./fixtures/production-halted.json";
import productionNewer from "./fixtures/production-newer.json";
import productionStagedNewer from "./fixtures/production-staged-newer.json";
import {
  COMMIT,
  EDIT_ID,
  PRODUCTION_RELEASES,
  TOKEN,
  changesAlreadyInReview,
  createFakePlay,
  emptyResponse,
  jsonResponse,
  playError,
} from "./support/fake-play";

// The orchestration (docs/store-readiness.md §5, Android): which Play calls are made, in which
// order, and — the safety properties — that a dry run never commits, that every non-committed edit
// is deleted, that a change already in review is never cancelled, and that a commit failure surfaces
// Play's own message. Verified against a stub `fetch` only; nothing here has touched the real Play API.

const NOTES = "Bug fixes and a faster map.";
const T = `/edits/${EDIT_ID}/tracks`;
const VALIDATE = `POST /edits/${EDIT_ID}:validate`;
const DELETE = `DELETE /edits/${EDIT_ID}`;

const READS = [
  "POST /edits",
  `GET ${T}/internal`,
  `GET ${T}/production`,
  `GET ${T}/alpha`,
  `GET /edits/${EDIT_ID}/listings`,
];

function setup(overrides = {}, clientOptions: { dryRun?: boolean } = {}) {
  const fake = createFakePlay(overrides);
  const api = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android", clientOptions);
  const log: string[] = [];
  const run = (options: { notes?: string | undefined; dryRun: boolean }) =>
    release({ api, notes: "notes" in options ? options.notes : NOTES, dryRun: options.dryRun, log: (l) => log.push(l) });
  return { fake, run, log };
}

describe("release() — real release", () => {
  it("makes exactly: insert, read 3 tracks + listings, update production + alpha, validate, commit, read production state", async () => {
    const { fake, run } = setup();
    const outcome = await run({ dryRun: false });
    expect(fake.sequence()).toEqual([
      ...READS,
      `PUT ${T}/production`,
      `PUT ${T}/alpha`,
      VALIDATE,
      COMMIT,
      PRODUCTION_RELEASES,
    ]);
    expect(outcome.kind).toBe("committed");
  });

  it("sends the same release — version codes, completed, notes per listing language — to both tracks", async () => {
    const { fake, run } = setup();
    await run({ dryRun: false });
    const notes = [
      { language: "en-GB", text: NOTES },
      { language: "nl-BE", text: NOTES },
    ];
    const puts = fake.calls.filter((c) => c.method === "PUT");
    expect(puts.map((c) => c.body)).toEqual([
      { track: "production", releases: [{ versionCodes: ["234"], status: "completed", releaseNotes: notes }] },
      { track: "alpha", releases: [{ versionCodes: ["234"], status: "completed", releaseNotes: notes }] },
    ]);
  });

  it("never deletes the edit it committed", async () => {
    const { fake, run } = setup();
    await run({ dryRun: false });
    expect(fake.calls.some((c) => c.method === "DELETE")).toBe(false);
  });

  it("returns the plan facts the summary needs: release name, codes, languages, before-state, production state", async () => {
    const { run } = setup();
    const outcome = await run({ dryRun: false });
    expect(outcome).toMatchObject({
      kind: "committed",
      name: "1.2.0 (234)",
      versionCodes: ["234"],
      languages: ["en-GB", "nl-BE"],
      before: { production: [], alpha: ["231"] },
      productionNow: [
        {
          name: "1.2.0 (234)",
          versionCodes: ["234"],
          status: "completed",
          lifecycleState: "RELEASE_LIFECYCLE_STATE_IN_REVIEW",
        },
      ],
    });
  });

  it("treats a 404 on the production/alpha track as an empty track", async () => {
    const { fake, run } = setup({
      [`GET ${T}/production`]: playError(404, "Track not found.", "NOT_FOUND"),
      [`GET ${T}/alpha`]: playError(404, "Track not found.", "NOT_FOUND"),
    });
    const outcome = await run({ dryRun: false });
    expect(outcome.kind).toBe("committed");
    expect(fake.sequence()).toContain(COMMIT);
  });

  it("a failing production-state read does not fail a committed release (best effort, warning logged)", async () => {
    const { run, log } = setup({ [PRODUCTION_RELEASES]: playError(403, "The caller does not have permission", "PERMISSION_DENIED") });
    const outcome = await run({ dryRun: false });
    expect(outcome.kind).toBe("committed");
    expect(outcome).toMatchObject({ productionNow: undefined });
    expect(log.join("\n")).toMatch(/could not read the production release state/i);
    expect(log.join("\n")).not.toContain(TOKEN);
  });
});

describe("release() — a change already in review is never cancelled", () => {
  it("stops cleanly when Play answers CHANGES_ALREADY_IN_REVIEW: outcome 'stopped', edit deleted, nothing committed", async () => {
    const { fake, run } = setup({ [COMMIT]: changesAlreadyInReview() });
    const outcome = await run({ dryRun: false });
    expect(outcome.kind).toBe("stopped");
    expect(fake.sequence()).toEqual([
      ...READS,
      `PUT ${T}/production`,
      `PUT ${T}/alpha`,
      VALIDATE,
      COMMIT,
      DELETE,
      PRODUCTION_RELEASES,
    ]);
  });

  it("the stopped outcome says why and still carries the release name and production state", async () => {
    const { run, log } = setup({ [COMMIT]: changesAlreadyInReview() });
    const outcome = await run({ dryRun: false });
    expect(outcome).toMatchObject({ kind: "stopped", reason: "changes-in-review", versionCodes: ["234"], name: "1.2.0 (234)" });
    expect(log.join("\n")).toMatch(/changes in review/i);
  });

  it("any OTHER commit refusal fails, deletes the edit, and names the next step", async () => {
    const reason = "Changes cannot be sent for review automatically.";
    const { fake, run } = setup({ [COMMIT]: playError(400, reason) });
    const failure = run({ dryRun: false });
    await expect(failure).rejects.toThrow(reason);
    await expect(failure).rejects.toThrow(/Publishing overview/);
    await expect(failure).rejects.toThrow(/Send changes for review/);
    expect(fake.sequence().at(-2)).toBe(COMMIT);
    expect(fake.sequence().at(-1)).toBe(DELETE);
  });

  it("the next step reads as its own sentence whether or not Play's message ends with a full stop", async () => {
    const withStop = setup({ [COMMIT]: playError(400, "Cannot be sent for review automatically.") });
    await expect(withStop.run({ dryRun: false })).rejects.toThrow(/automatically\. Next step: in Play Console/);
    const withoutStop = setup({ [COMMIT]: playError(400, "Cannot be sent for review automatically") });
    await expect(withoutStop.run({ dryRun: false })).rejects.toThrow(/automatically\. Next step: in Play Console/);
  });

  it("a network failure at commit time is not dressed up with a Play Console hint", async () => {
    const fake = createFakePlay();
    const api = new PlayClient(
      async (url, init) => {
        if (init?.method === "POST" && url.includes(":commit")) throw new Error("socket hang up");
        return fake.fetchFn(url, init);
      },
      TOKEN,
      "com.findly.android",
    );
    const failure = release({ api, notes: NOTES, dryRun: false });
    await expect(failure).rejects.toThrow(/network error/i);
    await failure.catch((e: Error) => expect(e.message).not.toMatch(/Publishing overview/));
  });

  it("never falls back to changesNotSentForReview or to cancelling the review", async () => {
    const { fake, run } = setup({ [COMMIT]: playError(400, "Changes cannot be sent for review automatically.") });
    await run({ dryRun: false }).catch(() => undefined);
    for (const call of fake.calls) {
      expect(call.url).not.toContain("changesNotSentForReview");
      expect(call.url).not.toContain("CANCEL_IN_REVIEW");
    }
    expect(fake.calls.filter((c) => c.path.includes(":commit"))).toHaveLength(1);
  });
});

describe("release() — dry run", () => {
  it("does every read and validation, then deletes the edit — never commits", async () => {
    const { fake, run } = setup();
    const outcome = await run({ dryRun: true });
    expect(fake.sequence()).toEqual([
      ...READS,
      `PUT ${T}/production`,
      `PUT ${T}/alpha`,
      VALIDATE,
      DELETE,
      PRODUCTION_RELEASES,
    ]);
    expect(fake.sequence().some((s) => s.includes(":commit"))).toBe(false);
    expect(outcome.kind).toBe("dry-run");
  });

  it("still reports the plan it would have applied", async () => {
    const { run } = setup();
    expect(await run({ dryRun: true })).toMatchObject({
      kind: "dry-run",
      versionCodes: ["234"],
      languages: ["en-GB", "nl-BE"],
    });
  });

  it("never commits when validation fails; deletes the edit and raises Play's message", async () => {
    const { fake, run } = setup({
      [VALIDATE]: playError(400, "Release notes for en-GB are too long."),
    });
    await expect(run({ dryRun: true })).rejects.toThrow(/Release notes for en-GB are too long/);
    expect(fake.sequence().some((s) => s.includes(":commit"))).toBe(false);
    expect(fake.sequence().at(-1)).toBe(DELETE);
  });

  it("a failing edit delete does not fail an otherwise good dry run (it logs a warning, no secret)", async () => {
    const { run, log } = setup({ [DELETE]: playError(500, "Internal error", "INTERNAL") });
    const outcome = await run({ dryRun: true });
    expect(outcome.kind).toBe("dry-run");
    expect(log.join("\n")).toMatch(/could not delete/i);
    expect(log.join("\n")).not.toContain(TOKEN);
  });

  it("is guarded structurally too: a dry-run client cannot commit even if the flag says 'real run'", async () => {
    const { fake, run } = setup({}, { dryRun: true });
    await expect(run({ dryRun: false })).rejects.toThrow(/dry run/i);
    expect(fake.sequence().some((s) => s.includes(":commit"))).toBe(false);
    expect(fake.sequence().at(-1)).toBe(DELETE);
  });
});

describe("release() — nothing to release", () => {
  const overrides = { [`GET ${T}/production`]: jsonResponse(productionCurrent) };

  it("deletes the edit, changes nothing, does not commit, then reads the production state", async () => {
    const { fake, run } = setup(overrides);
    const outcome = await run({ dryRun: false });
    expect(fake.sequence()).toEqual([...READS, DELETE, PRODUCTION_RELEASES]);
    expect(outcome).toMatchObject({
      kind: "nothing",
      versionCodes: ["234"],
      name: "1.2.0 (234)",
      before: { production: ["234"], alpha: ["231"] },
    });
  });

  it("is the same on a dry run", async () => {
    const { fake, run } = setup(overrides);
    const outcome = await run({ dryRun: true });
    expect(fake.sequence()).toEqual([...READS, DELETE, PRODUCTION_RELEASES]);
    expect(outcome.kind).toBe("nothing");
  });

  it("a failing production-state read does not fail it either", async () => {
    const { run } = setup({ ...overrides, [PRODUCTION_RELEASES]: playError(500, "Backend Error", "INTERNAL") });
    const outcome = await run({ dryRun: false });
    expect(outcome).toMatchObject({ kind: "nothing", productionNow: undefined });
  });
});

describe("release() — failures", () => {
  it("the original error wins when the cleanup delete fails too", async () => {
    const reason = "Changes cannot be sent for review automatically.";
    const { run } = setup({
      [COMMIT]: playError(400, reason),
      [DELETE]: emptyResponse(404),
    });
    await expect(run({ dryRun: false })).rejects.toThrow(reason);
  });

  it("fails when Internal has no completed release — no update, no commit, edit deleted", async () => {
    const { fake, run } = setup({ [`GET ${T}/internal`]: jsonResponse(internalNoCompleted) });
    await expect(run({ dryRun: false })).rejects.toThrow(/Internal testing/);
    expect(fake.sequence()).toEqual([...READS, DELETE]);
  });

  it("fails when the Internal track does not exist (404)", async () => {
    const { fake, run } = setup({ [`GET ${T}/internal`]: playError(404, "Track not found.", "NOT_FOUND") });
    await expect(run({ dryRun: false })).rejects.toThrow(/Internal testing/);
    expect(fake.sequence().some((s) => s.startsWith("PUT"))).toBe(false);
  });

  it("refuses a downgrade (production ahead of internal) and deletes the edit", async () => {
    const { fake, run } = setup({ [`GET ${T}/production`]: jsonResponse(productionNewer) });
    await expect(run({ dryRun: false })).rejects.toThrow(/downgrade/);
    expect(fake.sequence()).toEqual([...READS, DELETE]);
  });

  it("fails closed on a halted production release: no update, no commit, edit deleted", async () => {
    const { fake, run } = setup({ [`GET ${T}/production`]: jsonResponse(productionHalted) });
    await expect(run({ dryRun: false })).rejects.toThrow(/halted/);
    expect(fake.sequence()).toEqual([...READS, DELETE]);
  });

  it("fails closed on a staged production rollout that is not older than Internal's release", async () => {
    const { fake, run } = setup({ [`GET ${T}/production`]: jsonResponse(productionStagedNewer) });
    await expect(run({ dryRun: false })).rejects.toThrow(/staged rollout/);
    expect(fake.sequence()).toEqual([...READS, DELETE]);
  });

  it("stops after a failed track update: no second update, no validate, no commit", async () => {
    const { fake, run } = setup({
      [`PUT ${T}/production`]: playError(403, "The caller does not have permission", "PERMISSION_DENIED"),
    });
    await expect(run({ dryRun: false })).rejects.toThrow(/403.*does not have permission/);
    expect(fake.sequence()).toEqual([...READS, `PUT ${T}/production`, DELETE]);
  });

  it("makes no Play call at all when the notes are invalid", async () => {
    for (const notes of [undefined, "", "   ", "a".repeat(501)]) {
      const { fake, run } = setup();
      await expect(run({ notes, dryRun: false })).rejects.toThrow(/notes/i);
      expect(fake.calls).toHaveLength(0);
    }
  });

  it("deletes the edit when reading a track fails", async () => {
    const { fake, run } = setup({ [`GET ${T}/alpha`]: playError(500, "Backend Error", "INTERNAL") });
    await expect(run({ dryRun: false })).rejects.toThrow(/500/);
    expect(fake.sequence().at(-1)).toBe(DELETE);
  });
});

describe("release() — logging", () => {
  it("narrates the plan without ever printing the token", async () => {
    const { run, log } = setup();
    await run({ dryRun: true });
    const text = log.join("\n");
    expect(text).toMatch(/234/);
    expect(text).toMatch(/production/i);
    expect(text).toMatch(/alpha/i);
    expect(text).not.toContain(TOKEN);
  });
});
