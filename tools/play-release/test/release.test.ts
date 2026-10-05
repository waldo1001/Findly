import { describe, expect, it } from "vitest";
import { PlayClient } from "../src/play-client";
import { release } from "../src/release";
import internalNoCompleted from "./fixtures/internal-no-completed.json";
import productionCurrent from "./fixtures/production-current.json";
import productionNewer from "./fixtures/production-newer.json";
import {
  EDIT_ID,
  TOKEN,
  createFakePlay,
  emptyResponse,
  jsonResponse,
  playError,
} from "./support/fake-play";

// The orchestration (docs/store-readiness.md §5, Android): which Play calls are made, in which
// order, and — the safety properties — that a dry run never commits, that every non-committed edit
// is deleted, and that a commit failure surfaces Play's own message. Verified against a stub `fetch`
// only; nothing here has touched the real Play API.

const NOTES = "Bug fixes and a faster map.";
const T = `/edits/${EDIT_ID}/tracks`;

const READS = [
  "POST /edits",
  `GET ${T}/internal`,
  `GET ${T}/production`,
  `GET ${T}/alpha`,
  `GET /edits/${EDIT_ID}/listings`,
];

function setup(overrides = {}) {
  const fake = createFakePlay(overrides);
  const api = new PlayClient(fake.fetchFn, TOKEN, "com.findly.android");
  const log: string[] = [];
  const run = (options: { notes?: string | undefined; dryRun: boolean }) =>
    release({ api, notes: "notes" in options ? options.notes : NOTES, dryRun: options.dryRun, log: (l) => log.push(l) });
  return { fake, run, log };
}

describe("release() — real release", () => {
  it("makes exactly: insert, read 3 tracks + listings, update production + alpha, validate, commit", async () => {
    const { fake, run } = setup();
    const outcome = await run({ dryRun: false });
    expect(fake.sequence()).toEqual([
      ...READS,
      `PUT ${T}/production`,
      `PUT ${T}/alpha`,
      `POST /edits/${EDIT_ID}:validate`,
      `POST /edits/${EDIT_ID}:commit`,
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

  it("returns the plan facts the summary needs", async () => {
    const { run } = setup();
    const outcome = await run({ dryRun: false });
    expect(outcome).toMatchObject({
      kind: "committed",
      versionCodes: ["234"],
      languages: ["en-GB", "nl-BE"],
      before: { production: [], alpha: ["231"] },
    });
  });

  it("treats a 404 on the production/alpha track as an empty track", async () => {
    const { fake, run } = setup({
      [`GET ${T}/production`]: playError(404, "Track not found.", "NOT_FOUND"),
      [`GET ${T}/alpha`]: playError(404, "Track not found.", "NOT_FOUND"),
    });
    const outcome = await run({ dryRun: false });
    expect(outcome.kind).toBe("committed");
    expect(fake.sequence()).toContain(`POST /edits/${EDIT_ID}:commit`);
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
      `POST /edits/${EDIT_ID}:validate`,
      `DELETE /edits/${EDIT_ID}`,
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
      [`POST /edits/${EDIT_ID}:validate`]: playError(400, "Release notes for en-GB are too long."),
    });
    await expect(run({ dryRun: true })).rejects.toThrow(/Release notes for en-GB are too long/);
    expect(fake.sequence().some((s) => s.includes(":commit"))).toBe(false);
    expect(fake.sequence().at(-1)).toBe(`DELETE /edits/${EDIT_ID}`);
  });

  it("a failing edit delete does not fail an otherwise good dry run (it logs a warning, no secret)", async () => {
    const { run, log } = setup({ [`DELETE /edits/${EDIT_ID}`]: playError(500, "Internal error", "INTERNAL") });
    const outcome = await run({ dryRun: true });
    expect(outcome.kind).toBe("dry-run");
    expect(log.join("\n")).toMatch(/could not delete/i);
    expect(log.join("\n")).not.toContain(TOKEN);
  });
});

describe("release() — nothing to release", () => {
  const overrides = { [`GET ${T}/production`]: jsonResponse(productionCurrent) };

  it("deletes the edit, changes nothing and does not commit", async () => {
    const { fake, run } = setup(overrides);
    const outcome = await run({ dryRun: false });
    expect(fake.sequence()).toEqual([...READS, `DELETE /edits/${EDIT_ID}`]);
    expect(outcome).toMatchObject({ kind: "nothing", versionCodes: ["234"], production: ["234"] });
  });

  it("is the same on a dry run", async () => {
    const { fake, run } = setup(overrides);
    const outcome = await run({ dryRun: true });
    expect(fake.sequence()).toEqual([...READS, `DELETE /edits/${EDIT_ID}`]);
    expect(outcome.kind).toBe("nothing");
  });
});

describe("release() — failures", () => {
  it("surfaces Play's message when the commit is refused, and cleans the edit up afterwards", async () => {
    const reason = "Changes cannot be sent for review automatically.";
    const { fake, run } = setup({ [`POST /edits/${EDIT_ID}:commit`]: playError(400, reason) });
    await expect(run({ dryRun: false })).rejects.toThrow(reason);
    expect(fake.sequence().at(-2)).toBe(`POST /edits/${EDIT_ID}:commit`);
    expect(fake.sequence().at(-1)).toBe(`DELETE /edits/${EDIT_ID}`);
  });

  it("the original error wins when the cleanup delete fails too", async () => {
    const reason = "Changes cannot be sent for review automatically.";
    const { run } = setup({
      [`POST /edits/${EDIT_ID}:commit`]: playError(400, reason),
      [`DELETE /edits/${EDIT_ID}`]: emptyResponse(404),
    });
    await expect(run({ dryRun: false })).rejects.toThrow(reason);
  });

  it("fails when Internal has no completed release — no update, no commit, edit deleted", async () => {
    const { fake, run } = setup({ [`GET ${T}/internal`]: jsonResponse(internalNoCompleted) });
    await expect(run({ dryRun: false })).rejects.toThrow(/Internal testing/);
    expect(fake.sequence()).toEqual([...READS, `DELETE /edits/${EDIT_ID}`]);
  });

  it("fails when the Internal track does not exist (404)", async () => {
    const { fake, run } = setup({ [`GET ${T}/internal`]: playError(404, "Track not found.", "NOT_FOUND") });
    await expect(run({ dryRun: false })).rejects.toThrow(/Internal testing/);
    expect(fake.sequence().some((s) => s.startsWith("PUT"))).toBe(false);
  });

  it("refuses a downgrade (production ahead of internal) and deletes the edit", async () => {
    const { fake, run } = setup({ [`GET ${T}/production`]: jsonResponse(productionNewer) });
    await expect(run({ dryRun: false })).rejects.toThrow(/downgrade/);
    expect(fake.sequence()).toEqual([...READS, `DELETE /edits/${EDIT_ID}`]);
  });

  it("stops after a failed track update: no second update, no validate, no commit", async () => {
    const { fake, run } = setup({
      [`PUT ${T}/production`]: playError(403, "The caller does not have permission", "PERMISSION_DENIED"),
    });
    await expect(run({ dryRun: false })).rejects.toThrow(/403.*does not have permission/);
    expect(fake.sequence()).toEqual([...READS, `PUT ${T}/production`, `DELETE /edits/${EDIT_ID}`]);
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
    expect(fake.sequence().at(-1)).toBe(`DELETE /edits/${EDIT_ID}`);
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
