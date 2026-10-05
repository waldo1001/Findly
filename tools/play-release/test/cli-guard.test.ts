import { generateKeyPairSync } from "node:crypto";
import { beforeAll, describe, expect, it, vi } from "vitest";
import type { FetchFn } from "../src/auth";
import { run } from "../src/cli";
import type { PlayApi } from "../src/play-client";
import type { ReleaseOptions } from "../src/release";
import { COMMIT, TOKEN, createFakePlay, jsonResponse } from "./support/fake-play";

// Wiring test for the structural dry-run guard: the CLI must hand `release()` a client that
// physically cannot commit when DRY_RUN=true — independent of release()'s own flag check. `release`
// is replaced by a probe that keeps what it was given; everything else (auth, client, env parsing)
// is the real code, talking to the stub `fetch`.

const captured: ReleaseOptions[] = [];

vi.mock("../src/release", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/release")>();
  return {
    ...actual,
    release: vi.fn(async (options: ReleaseOptions) => {
      captured.push(options);
      return {
        kind: "nothing" as const,
        versionCodes: ["234"],
        before: { production: ["234"], alpha: [] },
        productionNow: [],
      };
    }),
  };
});

const TOKEN_URI = "https://oauth2.googleapis.com/token";
let saJson: string;

beforeAll(() => {
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  saJson = JSON.stringify({
    client_email: "findly-release@example-project.iam.gserviceaccount.test",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    token_uri: TOKEN_URI,
  });
});

async function runWith(dryRun: "true" | "false") {
  captured.length = 0;
  const fake = createFakePlay();
  const fetchFn: FetchFn = async (url, init) =>
    url === TOKEN_URI ? jsonResponse({ access_token: TOKEN })() : fake.fetchFn(url, init);
  const exitCode = await run(
    { PLAY_SERVICE_ACCOUNT_JSON: saJson, RELEASE_NOTES: "Bug fixes.", DRY_RUN: dryRun },
    { fetchFn, now: () => 1_760_000_000_000, log: () => undefined, mask: () => undefined },
  );
  const api: PlayApi = captured[0]!.api;
  return { exitCode, api, fake, options: captured[0]! };
}

describe("run() — structural dry-run guard", () => {
  it("DRY_RUN=true: the client handed to release() refuses to commit and sends no request", async () => {
    const { exitCode, api, fake, options } = await runWith("true");
    expect(exitCode).toBe(0);
    expect(options.dryRun).toBe(true);
    await expect(api.commit("EDIT123")).rejects.toThrow(/dry run/i);
    expect(fake.sequence()).not.toContain(COMMIT);
    expect(fake.calls).toHaveLength(0);
  });

  it("DRY_RUN=false: the client really can commit (the guard is not simply always on)", async () => {
    const { api, fake, options } = await runWith("false");
    expect(options.dryRun).toBe(false);
    expect(await api.commit("EDIT123")).toBe("committed");
    expect(fake.calls).toHaveLength(1);
  });
});
