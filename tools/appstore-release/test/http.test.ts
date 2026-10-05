import { describe, expect, it } from "vitest";
import { ASC_BASE_URL, AscApiError, AscClient, DryRunViolationError } from "../src/http";
import { createStubFetch, on } from "./stubFetch";

const TOKEN = "TOKEN-SENTINEL-abc.def.ghi";
const client = (stub: ReturnType<typeof createStubFetch>, dryRun = false) =>
  new AscClient({ token: () => TOKEN, dryRun, fetch: stub.fetch });

describe("AscClient requests", () => {
  it("GET sends the bearer token and JSON accept header to api.appstoreconnect.apple.com", async () => {
    const stub = createStubFetch([on("GET", "/v1/builds", { body: { data: [] } })]);
    await client(stub).get("/v1/builds", { "filter[app]": "6797994768", sort: "-uploadedDate" });
    const call = stub.calls[0]!;
    expect(new URL(call.url).origin).toBe("https://api.appstoreconnect.apple.com");
    expect(call.headers.authorization).toBe(`Bearer ${TOKEN}`);
    expect(call.headers.accept).toContain("application/json");
    expect(call.query).toEqual({ "filter[app]": "6797994768", sort: "-uploadedDate" });
  });

  it("POST and PATCH send a JSON body with a JSON content type", async () => {
    const stub = createStubFetch([
      on("POST", "/v1/reviewSubmissions", { status: 201, body: { data: { id: "rs1" } } }),
      on("PATCH", "/v1/reviewSubmissions/rs1", { body: { data: { id: "rs1" } } }),
    ]);
    const c = client(stub);
    await c.post("/v1/reviewSubmissions", { data: { type: "reviewSubmissions" } });
    await c.patch("/v1/reviewSubmissions/rs1", { data: { id: "rs1" } });
    expect(stub.calls[0]!.headers["content-type"]).toContain("application/json");
    expect(stub.calls[0]!.body).toEqual({ data: { type: "reviewSubmissions" } });
    expect(stub.calls[1]!.body).toEqual({ data: { id: "rs1" } });
  });

  it("returns undefined for 204 No Content (PATCH relationships/build, DELETE)", async () => {
    const stub = createStubFetch([
      on("PATCH", "/v1/appStoreVersions/v1/relationships/build", { status: 204 }),
      on("DELETE", "/v1/appStoreVersionPhasedReleases/p1", { status: 204 }),
    ]);
    const c = client(stub);
    expect(await c.patch("/v1/appStoreVersions/v1/relationships/build", { data: { type: "builds", id: "b" } })).toBeUndefined();
    expect(await c.delete("/v1/appStoreVersionPhasedReleases/p1")).toBeUndefined();
  });

  it("getOptional returns null on 404 and the document otherwise", async () => {
    const stub = createStubFetch([
      on("GET", "/v1/gone", { status: 404, body: { errors: [{ status: "404", code: "NOT_FOUND", title: "x", detail: "no" }] } }),
      on("GET", "/v1/here", { body: { data: { id: "1" } } }),
    ]);
    const c = client(stub);
    expect(await c.getOptional("/v1/gone")).toBeNull();
    expect(await c.getOptional("/v1/here")).toEqual({ data: { id: "1" } });
  });

  it("getOptional still throws on other errors", async () => {
    const stub = createStubFetch([on("GET", "/v1/x", { status: 403, body: { errors: [{ detail: "forbidden" }] } })]);
    await expect(client(stub).getOptional("/v1/x")).rejects.toBeInstanceOf(AscApiError);
  });
});

describe("DRY_RUN: GET requests only", () => {
  const mutations: Array<[string, (c: AscClient) => Promise<unknown>]> = [
    ["POST", (c) => c.post("/v1/appStoreVersions", { data: {} })],
    ["PATCH", (c) => c.patch("/v1/appStoreVersions/1", { data: {} })],
    ["DELETE", (c) => c.delete("/v1/appStoreVersionPhasedReleases/1")],
    ["PUT", (c) => c.request("PUT", "/v1/x")],
    ["HEAD", (c) => c.request("HEAD", "/v1/x")],
  ];

  for (const [method, run] of mutations) {
    it(`throws on ${method} before any network call`, async () => {
      const stub = createStubFetch([() => ({ body: { data: [] } })]);
      await expect(run(client(stub, true))).rejects.toBeInstanceOf(DryRunViolationError);
      expect(stub.calls).toHaveLength(0);
    });
  }

  it("still allows GET (including getOptional and getAll)", async () => {
    const stub = createStubFetch([() => ({ body: { data: [] } })]);
    const c = client(stub, true);
    await c.get("/v1/builds");
    await c.getOptional("/v1/builds");
    await c.getAll("/v1/builds");
    expect(stub.calls.map((x) => x.method)).toEqual(["GET", "GET", "GET"]);
  });

  it("is case-insensitive about the verb", async () => {
    const stub = createStubFetch([() => ({ body: { data: [] } })]);
    await expect(client(stub, true).request("post", "/v1/x")).rejects.toBeInstanceOf(DryRunViolationError);
    expect(stub.calls).toHaveLength(0);
  });
});

describe("errors surface Apple's errors[].detail", () => {
  it("includes status, request and every detail, and never the token", async () => {
    const stub = createStubFetch([
      on("PATCH", "/v1/appStoreVersions/v1", {
        status: 409,
        body: {
          errors: [
            { id: "e1", status: "409", code: "ENTITY_ERROR.ATTRIBUTE.INVALID", title: "Invalid", detail: "The version string is not valid." },
            { id: "e2", status: "409", code: "STATE_ERROR", title: "State", detail: "Cannot edit in WAITING_FOR_REVIEW." },
          ],
        },
      }),
    ]);
    const err = (await client(stub)
      .patch("/v1/appStoreVersions/v1", { data: {} })
      .catch((e: unknown) => e)) as AscApiError;
    expect(err).toBeInstanceOf(AscApiError);
    expect(err.status).toBe(409);
    expect(err.message).toContain("409");
    expect(err.message).toContain("PATCH /v1/appStoreVersions/v1");
    expect(err.message).toContain("The version string is not valid.");
    expect(err.message).toContain("Cannot edit in WAITING_FOR_REVIEW.");
    expect(err.message).not.toContain(TOKEN);
    expect(err.errors.map((e) => e.code)).toEqual(["ENTITY_ERROR.ATTRIBUTE.INVALID", "STATE_ERROR"]);
  });

  it("falls back to title/code when an error has no detail", async () => {
    const stub = createStubFetch([on("GET", "/v1/x", { status: 401, body: { errors: [{ code: "NOT_AUTHORIZED", title: "Authentication credentials are missing or invalid." }] } })]);
    await expect(client(stub).get("/v1/x")).rejects.toThrow(/Authentication credentials are missing or invalid/);
  });

  it("copes with a non-JSON error body (e.g. a proxy 502)", async () => {
    const stub = createStubFetch([on("GET", "/v1/x", { status: 502, body: "<html>Bad gateway</html>" })]);
    const err = (await client(stub).get("/v1/x").catch((e: unknown) => e)) as AscApiError;
    expect(err).toBeInstanceOf(AscApiError);
    expect(err.status).toBe(502);
    expect(err.message).toContain("502");
    expect(err.message).not.toContain("<html>");
  });

  it("wraps a network failure with the request line and without the token", async () => {
    const failing = (async () => {
      throw new Error(`socket hang up (Authorization: Bearer ${TOKEN})`);
    }) as unknown as typeof fetch;
    const c = new AscClient({ token: () => TOKEN, dryRun: false, fetch: failing });
    const err = (await c.get("/v1/builds").catch((e: unknown) => e)) as Error;
    expect(err.message).toContain("GET /v1/builds");
    expect(err.message).not.toContain(TOKEN);
  });

  it("does not leak the token through a thrown dry-run violation either", async () => {
    const stub = createStubFetch([]);
    const err = (await client(stub, true).post("/v1/x", {}).catch((e: unknown) => e)) as Error;
    expect(err.message).toContain("POST /v1/x");
    expect(err.message).not.toContain(TOKEN);
  });
});

describe("getAll follows links.next", () => {
  it("concatenates data and included across pages", async () => {
    const stub = createStubFetch([
      (call) =>
        call.pathAndQuery.startsWith("/v1/builds?") && !call.query.cursor
          ? {
              body: {
                data: [{ id: "a" }],
                included: [{ id: "i1" }],
                links: { next: "https://api.appstoreconnect.apple.com/v1/builds?cursor=2&limit=1" },
              },
            }
          : undefined,
      (call) => (call.query.cursor === "2" ? { body: { data: [{ id: "b" }], included: [{ id: "i2" }] } } : undefined),
    ]);
    const all = await client(stub).getAll<{ id: string }>("/v1/builds", { limit: "1" });
    expect(all.data.map((d) => d.id)).toEqual(["a", "b"]);
    expect(all.included.map((d) => d.id)).toEqual(["i1", "i2"]);
    expect(stub.calls).toHaveLength(2);
    expect(stub.calls[1]!.headers.authorization).toBe(`Bearer ${TOKEN}`);
  });

  it("refuses a next link to another host, so the bearer token is never sent elsewhere", async () => {
    const stub = createStubFetch([
      on("GET", "/v1/builds", { body: { data: [{ id: "a" }], links: { next: "https://evil.example/steal" } } }),
    ]);
    await expect(client(stub).getAll("/v1/builds")).rejects.toThrow(/unexpected host/i);
    expect(stub.calls).toHaveLength(1);
  });

  it("gives up after a bounded number of pages instead of looping forever", async () => {
    const stub = createStubFetch([
      () => ({ body: { data: [{ id: "x" }], links: { next: "https://api.appstoreconnect.apple.com/v1/builds?cursor=again" } } }),
    ]);
    await expect(client(stub).getAll("/v1/builds")).rejects.toThrow(/pages/i);
    expect(stub.calls.length).toBeLessThanOrEqual(11);
  });
});

describe("the bearer token only ever goes to the App Store Connect origin", () => {
  it("pins the origin", () => {
    expect(ASC_BASE_URL).toBe("https://api.appstoreconnect.apple.com");
  });

  for (const evil of ["https://evil.example/steal", "//evil.example/steal", "http://api.appstoreconnect.apple.com/v1/builds", "https://api.appstoreconnect.apple.com.evil.example/v1/builds"]) {
    it(`refuses a request resolved to ${evil}, before any network call`, async () => {
      const stub = createStubFetch([() => ({ body: { data: [] } })]);
      const err = (await client(stub).get(evil).catch((e: unknown) => e)) as Error;
      expect(err).toBeInstanceOf(Error);
      expect(err.message).toMatch(/origin/i);
      expect(err.message).not.toContain(TOKEN);
      expect(stub.calls).toHaveLength(0);
    });
  }

  it("also refuses mutating requests to another origin", async () => {
    const stub = createStubFetch([() => ({ body: { data: [] } })]);
    await expect(client(stub).post("https://evil.example/x", {})).rejects.toThrow(/origin/i);
    expect(stub.calls).toHaveLength(0);
  });

  it("never follows a redirect (a 3xx would carry the Authorization header elsewhere)", async () => {
    const stub = createStubFetch([() => ({ body: { data: [] } })]);
    await client(stub).get("/v1/builds");
    await client(stub).post("/v1/reviewSubmissions", {});
    expect(stub.calls.map((c) => c.redirect)).toEqual(["error", "error"]);
  });

  it("has no way to point the client at another base URL", () => {
    // @ts-expect-error baseUrl is deliberately not an option
    new AscClient({ token: () => TOKEN, dryRun: true, baseUrl: "https://evil.example" });
  });
});
