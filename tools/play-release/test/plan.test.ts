import { describe, expect, it } from "vitest";
import { MAX_NOTES_LENGTH, plan } from "../src/plan";
import type { PlanRelease, Track } from "../src/plan";
import internalCompleted from "./fixtures/internal-completed.json";
import internalMixed from "./fixtures/internal-mixed.json";
import internalNoCompleted from "./fixtures/internal-no-completed.json";
import internalMultiCode from "./fixtures/internal-multi-code.json";
import internalTwoCompleted from "./fixtures/internal-two-completed.json";
import trackEmpty from "./fixtures/track-empty.json";
import productionCurrent from "./fixtures/production-current.json";
import productionOlder from "./fixtures/production-older.json";
import productionNewer from "./fixtures/production-newer.json";
import productionStaged from "./fixtures/production-staged-rollout.json";
import alphaOlder from "./fixtures/alpha-older.json";
import listings from "./fixtures/listings.json";

// docs/store-readiness.md §5 (Android, steps 1-4). Fixtures are shaped like real
// androidpublisher v3 `edits.tracks.get` / `edits.listings.list` responses: versionCodes are
// strings (int64), an empty track carries no `releases` key at all.
const languages = listings.listings.map((l) => l.language);
const NOTES = "Bug fixes and a faster map.";

function asRelease(result: ReturnType<typeof plan>): PlanRelease {
  expect(result.action).toBe("release");
  return result as PlanRelease;
}

describe("plan() — what to release", () => {
  it("promotes internal's completed release when production is empty", () => {
    const result = plan(
      { internal: internalCompleted, production: trackEmpty, alpha: trackEmpty },
      languages,
      NOTES,
    );
    const release = asRelease(result);
    expect(release.versionCodes).toEqual(["234"]);
    const expectedNotes = [
      { language: "en-GB", text: NOTES },
      { language: "nl-BE", text: NOTES },
    ];
    expect(release.bodies.production).toEqual({
      track: "production",
      releases: [{ versionCodes: ["234"], status: "completed", releaseNotes: expectedNotes }],
    });
    expect(release.bodies.alpha).toEqual({
      track: "alpha",
      releases: [{ versionCodes: ["234"], status: "completed", releaseNotes: expectedNotes }],
    });
  });

  it("sets no userFraction and no name — a full, plain 'completed' rollout", () => {
    const release = asRelease(
      plan({ internal: internalCompleted, production: trackEmpty, alpha: trackEmpty }, languages, NOTES),
    );
    for (const body of [release.bodies.production, release.bodies.alpha]) {
      expect(Object.keys(body.releases[0]!).sort()).toEqual(["releaseNotes", "status", "versionCodes"]);
    }
  });

  it("ignores draft and halted releases on internal and takes the completed one", () => {
    const release = asRelease(
      plan({ internal: internalMixed, production: trackEmpty, alpha: trackEmpty }, languages, NOTES),
    );
    expect(release.versionCodes).toEqual(["234"]);
  });

  it("takes every version code of the completed release, sorted numerically", () => {
    const release = asRelease(
      plan({ internal: internalMultiCode, production: trackEmpty, alpha: trackEmpty }, languages, NOTES),
    );
    expect(release.versionCodes).toEqual(["233", "234"]);
    expect(release.bodies.production.releases[0]!.versionCodes).toEqual(["233", "234"]);
  });

  it("sorts version codes numerically, not lexically ('9' < '10')", () => {
    const internal: Track = {
      track: "internal",
      releases: [{ versionCodes: ["10", "9"], status: "completed" }],
    };
    const release = asRelease(plan({ internal, production: trackEmpty, alpha: trackEmpty }, languages, NOTES));
    expect(release.versionCodes).toEqual(["9", "10"]);
  });

  it("with several completed releases on internal, the one carrying the highest version code is current", () => {
    const release = asRelease(
      plan({ internal: internalTwoCompleted, production: trackEmpty, alpha: trackEmpty }, languages, NOTES),
    );
    expect(release.versionCodes).toEqual(["234"]);
  });

  it("ignores a completed release that carries no version codes", () => {
    const internal: Track = {
      track: "internal",
      releases: [{ status: "completed" }, { versionCodes: [], status: "completed" }, ...internalCompleted.releases],
    };
    const release = asRelease(plan({ internal, production: trackEmpty, alpha: trackEmpty }, languages, NOTES));
    expect(release.versionCodes).toEqual(["234"]);
  });

  it("releases when production carries an older completed release", () => {
    const release = asRelease(
      plan({ internal: internalCompleted, production: productionOlder, alpha: alphaOlder }, languages, NOTES),
    );
    expect(release.versionCodes).toEqual(["234"]);
    expect(release.before).toEqual({ production: ["230"], alpha: ["231"] });
  });

  it("releases when production only has a staged (inProgress) rollout of that version", () => {
    // Only a `completed` release counts as "already released" (store-readiness §5 step 4).
    const release = asRelease(
      plan({ internal: internalCompleted, production: productionStaged, alpha: trackEmpty }, languages, NOTES),
    );
    expect(release.versionCodes).toEqual(["234"]);
    expect(release.before.production).toEqual(["230"]);
  });

  it("reports empty before-state for tracks without releases", () => {
    const release = asRelease(
      plan({ internal: internalCompleted, production: trackEmpty, alpha: undefined }, languages, NOTES),
    );
    expect(release.before).toEqual({ production: [], alpha: [] });
  });

  it("treats a missing (undefined) production track as empty", () => {
    const release = asRelease(plan({ internal: internalCompleted, production: undefined }, languages, NOTES));
    expect(release.versionCodes).toEqual(["234"]);
  });
});

describe("plan() — nothing to release", () => {
  it("reports nothing when production already has a completed release with exactly those version codes", () => {
    const result = plan(
      { internal: internalCompleted, production: productionCurrent, alpha: alphaOlder },
      languages,
      NOTES,
    );
    expect(result).toEqual({ action: "nothing", versionCodes: ["234"], production: ["234"], alpha: ["231"] });
  });

  it("compares version codes as a set — order does not matter", () => {
    const production: Track = {
      track: "production",
      releases: [{ versionCodes: ["234", "233"], status: "completed" }],
    };
    const result = plan({ internal: internalMultiCode, production, alpha: trackEmpty }, languages, NOTES);
    expect(result.action).toBe("nothing");
  });

  it("is not 'nothing' when production has only a subset of the version codes", () => {
    const production: Track = { track: "production", releases: [{ versionCodes: ["234"], status: "completed" }] };
    const result = plan({ internal: internalMultiCode, production, alpha: trackEmpty }, languages, NOTES);
    expect(result.action).toBe("release");
  });

  it("still validates the notes before reporting nothing to release", () => {
    const result = plan({ internal: internalCompleted, production: productionCurrent }, languages, "  ");
    expect(result).toMatchObject({ action: "error", code: "notes-empty" });
  });
});

describe("plan() — errors", () => {
  it("fails when internal has no completed release (draft + halted only)", () => {
    const result = plan({ internal: internalNoCompleted, production: trackEmpty }, languages, NOTES);
    expect(result).toMatchObject({ action: "error", code: "no-internal-release" });
  });

  it("fails when internal has no releases at all", () => {
    const result = plan({ internal: { track: "internal" }, production: trackEmpty }, languages, NOTES);
    expect(result).toMatchObject({ action: "error", code: "no-internal-release" });
  });

  it("fails when the internal track does not exist (undefined)", () => {
    const result = plan({ internal: undefined, production: trackEmpty }, languages, NOTES);
    expect(result).toMatchObject({ action: "error", code: "no-internal-release" });
    expect((result as { message: string }).message).toMatch(/internal/i);
  });

  it("refuses to downgrade when production is ahead of internal", () => {
    const result = plan({ internal: internalCompleted, production: productionNewer }, languages, NOTES);
    expect(result).toMatchObject({ action: "error", code: "production-ahead" });
    const message = (result as { message: string }).message;
    expect(message).toContain("240");
    expect(message).toContain("234");
  });
});

describe("plan() — release-notes languages", () => {
  const base = { internal: internalCompleted, production: trackEmpty, alpha: trackEmpty };
  const languagesOf = (result: ReturnType<typeof plan>) =>
    asRelease(result).bodies.production.releases[0]!.releaseNotes.map((n) => n.language);

  it("covers every listing language, en-GB first", () => {
    expect(languagesOf(plan(base, ["nl-BE", "fr-FR", "en-GB"], NOTES))).toEqual(["en-GB", "nl-BE", "fr-FR"]);
  });

  it("always includes en-GB even when the listing has no such language", () => {
    expect(languagesOf(plan(base, ["nl-BE"], NOTES))).toEqual(["en-GB", "nl-BE"]);
  });

  it("falls back to en-GB alone when no listings exist", () => {
    expect(languagesOf(plan(base, [], NOTES))).toEqual(["en-GB"]);
  });

  it("deduplicates repeated languages", () => {
    expect(languagesOf(plan(base, ["en-GB", "nl-BE", "nl-BE", "en-GB"], NOTES))).toEqual(["en-GB", "nl-BE"]);
  });

  it("uses the same text for every language", () => {
    const texts = asRelease(plan(base, languages, NOTES)).bodies.alpha.releases[0]!.releaseNotes.map((n) => n.text);
    expect(new Set(texts)).toEqual(new Set([NOTES]));
  });

  it("exposes the languages on the plan for the summary", () => {
    expect(asRelease(plan(base, languages, NOTES)).languages).toEqual(["en-GB", "nl-BE"]);
  });
});

describe("plan() — release-notes validation", () => {
  const tracks = { internal: internalCompleted, production: trackEmpty, alpha: trackEmpty };

  it("trims surrounding whitespace", () => {
    const release = asRelease(plan(tracks, languages, "  \n Fixed the map.\t\n"));
    expect(release.notes).toBe("Fixed the map.");
    expect(release.bodies.production.releases[0]!.releaseNotes[0]!.text).toBe("Fixed the map.");
  });

  it("keeps inner newlines", () => {
    const release = asRelease(plan(tracks, languages, "Line one\nLine two"));
    expect(release.notes).toBe("Line one\nLine two");
  });

  it("rejects undefined notes", () => {
    expect(plan(tracks, languages, undefined)).toMatchObject({ action: "error", code: "notes-empty" });
  });

  it("rejects empty notes", () => {
    expect(plan(tracks, languages, "")).toMatchObject({ action: "error", code: "notes-empty" });
  });

  it("rejects whitespace-only notes", () => {
    expect(plan(tracks, languages, " \n\t  ")).toMatchObject({ action: "error", code: "notes-empty" });
  });

  it("accepts exactly 500 characters", () => {
    expect(MAX_NOTES_LENGTH).toBe(500);
    expect(plan(tracks, languages, "a".repeat(500)).action).toBe("release");
  });

  it("rejects 501 characters with a message naming the limit and the actual length", () => {
    const result = plan(tracks, languages, "a".repeat(501));
    expect(result).toMatchObject({ action: "error", code: "notes-too-long" });
    const message = (result as { message: string }).message;
    expect(message).toContain("500");
    expect(message).toContain("501");
  });

  it("measures the limit after trimming — padding does not count", () => {
    expect(plan(tracks, languages, `   ${"a".repeat(500)}   `).action).toBe("release");
  });

  it("reports a bad note before a missing internal release (notes are checked first)", () => {
    const result = plan({ internal: undefined, production: trackEmpty }, languages, "");
    expect(result).toMatchObject({ action: "error", code: "notes-empty" });
  });
});
