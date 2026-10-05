import { createPublicKey, createVerify, generateKeyPairSync } from "node:crypto";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { PLAY_SCOPE, buildJwt, fetchAccessToken, parseServiceAccount } from "../src/auth";
import type { FetchFn, ServiceAccount } from "../src/auth";

// A throwaway RSA key generated at test time — nothing key-shaped is ever committed.
let privateKeyPem: string;
let publicKeyPem: string;
const TOKEN_URI = "https://oauth2.googleapis.com/token";
const EMAIL = "findly-release@example-project.iam.gserviceaccount.test";
const NOW = 1_760_000_000;

beforeAll(() => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  publicKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();
});

function saJson(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    type: "service_account",
    client_email: EMAIL,
    private_key: privateKeyPem,
    token_uri: TOKEN_URI,
    ...overrides,
  });
}

function decodeSegment(segment: string): unknown {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
}

describe("parseServiceAccount()", () => {
  it("reads client_email and the private key", () => {
    const sa = parseServiceAccount(saJson());
    expect(sa.clientEmail).toBe(EMAIL);
    expect(sa.privateKey).toBe(privateKeyPem);
  });

  it("accepts a service account without a token_uri (the endpoint is pinned in code anyway)", () => {
    expect(() => parseServiceAccount(saJson({ token_uri: undefined }))).not.toThrow();
  });

  it("accepts exactly Google's token endpoint", () => {
    expect(() => parseServiceAccount(saJson({ token_uri: "https://oauth2.googleapis.com/token" }))).not.toThrow();
  });

  it.each([
    "http://oauth2.googleapis.com/token",
    "https://oauth2.googleapis.com/token/",
    "https://oauth2.googleapis.com/token?x=1",
    "https://oauth2.googleapis.com.evil.example/token",
    "https://evil.example/token-marker-xyz",
    "https://accounts.google.com/o/oauth2/token",
    "not a url",
    "",
  ])("rejects any other token_uri (%j) — the signed assertion must never be sent elsewhere", (uri) => {
    let message = "";
    try {
      parseServiceAccount(saJson({ token_uri: uri }));
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toMatch(/token_uri/);
    expect(message).toContain("https://oauth2.googleapis.com/token");
    // The offending value is never echoed back.
    expect(message).not.toContain("evil.example");
    expect(message).not.toContain("marker-xyz");
  });

  it("rejects a non-string token_uri", () => {
    expect(() => parseServiceAccount(saJson({ token_uri: 42 }))).toThrow(/token_uri/);
  });

  it.each([undefined, "", "   "])("rejects missing/empty JSON (%j)", (value) => {
    expect(() => parseServiceAccount(value)).toThrow(/PLAY_SERVICE_ACCOUNT_JSON/);
  });

  it("rejects JSON that lacks client_email", () => {
    expect(() => parseServiceAccount(saJson({ client_email: undefined }))).toThrow(/client_email/);
  });

  it("rejects JSON that lacks a private key", () => {
    expect(() => parseServiceAccount(saJson({ private_key: undefined }))).toThrow(/private_key/);
  });

  it("rejects non-JSON without echoing any of it (the parser's own message quotes the input)", () => {
    const secretish = "{ this is not json but contains-a-sensitive-marker-12345";
    let message = "";
    try {
      parseServiceAccount(secretish);
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toMatch(/not valid JSON/);
    expect(message).not.toContain("sensitive-marker");
    expect(message).not.toContain("this is not json");
  });

  it("rejects JSON that is not an object", () => {
    expect(() => parseServiceAccount('"just a string"')).toThrow(/object/);
    expect(() => parseServiceAccount("null")).toThrow(/object/);
  });
});

describe("buildJwt()", () => {
  const sa = (): ServiceAccount => parseServiceAccount(saJson());

  it("has three base64url segments with no padding", () => {
    const jwt = buildJwt(sa(), NOW);
    const parts = jwt.split(".");
    expect(parts).toHaveLength(3);
    for (const part of parts) expect(part).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it("header is RS256 / JWT", () => {
    const [header] = buildJwt(sa(), NOW).split(".");
    expect(decodeSegment(header!)).toEqual({ alg: "RS256", typ: "JWT" });
  });

  it("claims: iss = client_email, androidpublisher scope, aud = token_uri, iat = now, exp within one hour", () => {
    const [, claims] = buildJwt(sa(), NOW).split(".");
    expect(decodeSegment(claims!)).toEqual({
      iss: EMAIL,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: TOKEN_URI,
      iat: NOW,
      exp: NOW + 3600,
    });
    expect(PLAY_SCOPE).toBe("https://www.googleapis.com/auth/androidpublisher");
  });

  it("lifetime is at most one hour (Google rejects longer)", () => {
    const [, claims] = buildJwt(sa(), NOW).split(".");
    const { iat, exp } = decodeSegment(claims!) as { iat: number; exp: number };
    expect(exp - iat).toBeLessThanOrEqual(3600);
    expect(exp - iat).toBeGreaterThan(0);
  });

  it("signature verifies against the matching public key (RS256 = RSASSA-PKCS1-v1_5 + SHA-256)", () => {
    const jwt = buildJwt(sa(), NOW);
    const [header, claims, signature] = jwt.split(".");
    const ok = createVerify("RSA-SHA256")
      .update(`${header}.${claims}`)
      .verify(createPublicKey(publicKeyPem), Buffer.from(signature!, "base64url"));
    expect(ok).toBe(true);
  });

  it("signature does not verify after tampering with the claims", () => {
    const [header, , signature] = buildJwt(sa(), NOW).split(".");
    const forged = Buffer.from(JSON.stringify({ iss: "someone-else" })).toString("base64url");
    const ok = createVerify("RSA-SHA256")
      .update(`${header}.${forged}`)
      .verify(createPublicKey(publicKeyPem), Buffer.from(signature!, "base64url"));
    expect(ok).toBe(false);
  });

  it("an unusable private key fails with a generic message that does not echo the key", () => {
    const junk = "-----not a pem-----\nZm9vYmFyLXNlY3JldC1tYXJrZXI=\n";
    let message = "";
    try {
      buildJwt({ ...sa(), privateKey: junk }, NOW);
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toMatch(/sign/i);
    expect(message).not.toContain("Zm9vYmFy");
    expect(message).not.toContain("not a pem");
  });
});

function tokenResponse(body: unknown, status = 200): Response {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

describe("fetchAccessToken()", () => {
  const sa = (): ServiceAccount => parseServiceAccount(saJson());

  it("registers a mask for the signed assertion BEFORE the token request, and for the access token right after it", async () => {
    const events: string[] = [];
    const fetchFn = vi.fn<FetchFn>(async () => {
      events.push("fetch");
      return tokenResponse({ access_token: "ya29.fake-test-token", expires_in: 3599, token_type: "Bearer" });
    });
    const masked: string[] = [];
    const token = await fetchAccessToken(fetchFn, sa(), NOW, (secret) => {
      masked.push(secret);
      events.push(`mask:${masked.length}`);
    });
    expect(token).toBe("ya29.fake-test-token");
    expect(masked).toEqual([buildJwt(sa(), NOW), "ya29.fake-test-token"]);
    expect(events).toEqual(["mask:1", "fetch", "mask:2"]);
  });

  it("still masks the assertion when the exchange fails, and never masks a token that was not issued", async () => {
    const fetchFn = vi.fn<FetchFn>(async () => tokenResponse({ error: "invalid_grant" }, 400));
    const masked: string[] = [];
    await expect(fetchAccessToken(fetchFn, sa(), NOW, (s) => masked.push(s))).rejects.toThrow(/invalid_grant/);
    expect(masked).toEqual([buildJwt(sa(), NOW)]);
  });

  it("POSTs the signed assertion as a form to token_uri and returns the access token", async () => {
    const fetchFn = vi.fn<FetchFn>(async () =>
      tokenResponse({ access_token: "ya29.fake-test-token", expires_in: 3599, token_type: "Bearer" }),
    );
    const token = await fetchAccessToken(fetchFn, sa(), NOW);
    expect(token).toBe("ya29.fake-test-token");

    expect(fetchFn).toHaveBeenCalledTimes(1);
    const [url, init] = fetchFn.mock.calls[0]!;
    expect(url).toBe(TOKEN_URI);
    expect(init?.method).toBe("POST");
    expect((init?.headers as Record<string, string>)["content-type"]).toBe("application/x-www-form-urlencoded");
    const form = new URLSearchParams(String(init?.body));
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    expect(form.get("assertion")).toBe(buildJwt(sa(), NOW));
  });

  it("surfaces Google's error and description on a rejected exchange — never the assertion", async () => {
    const fetchFn = vi.fn<FetchFn>(async () =>
      tokenResponse({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, 400),
    );
    const failure = fetchAccessToken(fetchFn, sa(), NOW);
    await expect(failure).rejects.toThrow(/invalid_grant/);
    await expect(failure).rejects.toThrow(/Invalid JWT Signature/);
    await expect(failure).rejects.toThrow(/400/);
    const jwt = buildJwt(sa(), NOW);
    await failure.catch((e: Error) => {
      expect(e.message).not.toContain(jwt);
      expect(e.message).not.toContain(privateKeyPem);
    });
  });

  it("fails clearly when the response has no access_token", async () => {
    const fetchFn = vi.fn<FetchFn>(async () => tokenResponse({ token_type: "Bearer" }));
    await expect(fetchAccessToken(fetchFn, sa(), NOW)).rejects.toThrow(/access_token/);
  });

  it("fails clearly on a non-JSON error body without echoing it", async () => {
    const fetchFn = vi.fn<FetchFn>(async () => new Response("<html>Bad Gateway sensitive-marker</html>", { status: 502 }));
    const failure = fetchAccessToken(fetchFn, sa(), NOW);
    await expect(failure).rejects.toThrow(/502/);
    await failure.catch((e: Error) => expect(e.message).not.toContain("sensitive-marker"));
  });

  it("fails clearly when the network call itself throws, without leaking the request body", async () => {
    const fetchFn = vi.fn<FetchFn>(async (_url, init) => {
      throw new Error(`socket hang up while sending ${String(init?.body)}`);
    });
    const failure = fetchAccessToken(fetchFn, sa(), NOW);
    await expect(failure).rejects.toThrow(/token endpoint/i);
    await failure.catch((e: Error) => {
      expect(e.message).not.toContain("assertion");
      expect(e.message).not.toContain(buildJwt(sa(), NOW));
    });
  });
});
