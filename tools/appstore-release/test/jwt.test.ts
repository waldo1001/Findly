import { generateKeyPairSync, verify, type KeyObject } from "node:crypto";
import { describe, expect, it } from "vitest";
import { createToken, createTokenProvider, normalizePrivateKey } from "../src/jwt";

// Generated per run — no key material is ever committed (docs/security-review-checklist.md §1).
function testKeyPair(): { privatePem: string; publicKey: KeyObject } {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return { privatePem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(), publicKey };
}

const b64urlJson = (segment: string): unknown =>
  JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));

const BASE = { keyId: "FAKEKEY123", issuerId: "11111111-2222-3333-4444-555555555555" };

describe("createToken (ES256 JWT for App Store Connect)", () => {
  const { privatePem, publicKey } = testKeyPair();

  it("has three unpadded base64url segments", () => {
    const token = createToken({ ...BASE, privateKey: privatePem, now: 1_700_000_000 });
    const parts = token.split(".");
    expect(parts).toHaveLength(3);
    for (const p of parts) expect(p).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it("header is exactly {alg: ES256, kid, typ: JWT}", () => {
    const token = createToken({ ...BASE, privateKey: privatePem, now: 1_700_000_000 });
    expect(b64urlJson(token.split(".")[0]!)).toEqual({ alg: "ES256", kid: "FAKEKEY123", typ: "JWT" });
  });

  it("claims are exactly {iss, iat, exp, aud} with aud appstoreconnect-v1", () => {
    const token = createToken({ ...BASE, privateKey: privatePem, now: 1_700_000_000 });
    const claims = b64urlJson(token.split(".")[1]!) as Record<string, unknown>;
    expect(Object.keys(claims).sort()).toEqual(["aud", "exp", "iat", "iss"]);
    expect(claims.iss).toBe(BASE.issuerId);
    expect(claims.aud).toBe("appstoreconnect-v1");
    expect(claims.iat).toBe(1_700_000_000);
  });

  it("defaults to a lifetime of at most 20 minutes (Apple rejects longer)", () => {
    const token = createToken({ ...BASE, privateKey: privatePem, now: 1_700_000_000 });
    const claims = b64urlJson(token.split(".")[1]!) as { iat: number; exp: number };
    expect(claims.exp - claims.iat).toBeGreaterThan(0);
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(20 * 60);
  });

  it("refuses a lifetime above 20 minutes or non-positive", () => {
    expect(() => createToken({ ...BASE, privateKey: privatePem, now: 1, lifetimeSeconds: 20 * 60 + 1 })).toThrow(
      /20 minutes/,
    );
    expect(() => createToken({ ...BASE, privateKey: privatePem, now: 1, lifetimeSeconds: 0 })).toThrow();
  });

  it("accepts exactly 20 minutes", () => {
    const token = createToken({ ...BASE, privateKey: privatePem, now: 100, lifetimeSeconds: 20 * 60 });
    const claims = b64urlJson(token.split(".")[1]!) as { iat: number; exp: number };
    expect(claims.exp - claims.iat).toBe(20 * 60);
  });

  it("signs with ES256 in IEEE P1363 form: 64 raw bytes that verify against the public key", () => {
    const token = createToken({ ...BASE, privateKey: privatePem, now: 1_700_000_000 });
    const [h, p, s] = token.split(".") as [string, string, string];
    const sig = Buffer.from(s, "base64url");
    expect(sig.length).toBe(64);
    const ok = verify("sha256", Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, sig);
    expect(ok).toBe(true);
  });

  it("the signature does not verify against a different key or a tampered payload", () => {
    const other = testKeyPair();
    const token = createToken({ ...BASE, privateKey: privatePem, now: 1_700_000_000 });
    const [h, p, s] = token.split(".") as [string, string, string];
    const sig = Buffer.from(s, "base64url");
    expect(verify("sha256", Buffer.from(`${h}.${p}`), { key: other.publicKey, dsaEncoding: "ieee-p1363" }, sig)).toBe(
      false,
    );
    expect(verify("sha256", Buffer.from(`${h}.${p}x`), { key: publicKey, dsaEncoding: "ieee-p1363" }, sig)).toBe(
      false,
    );
  });

  it("an unusable key throws without echoing key material", () => {
    // Built at runtime so the repo's secret-scan grep (security-review-checklist §1) never sees a PEM header here.
    const secretish = `-----BEGIN ${"PRIVATE"} KEY-----\nTOPSECRETMATERIAL\n-----END ${"PRIVATE"} KEY-----`;
    let message = "";
    try {
      createToken({ ...BASE, privateKey: secretish, now: 1 });
    } catch (e) {
      message = String((e as Error).message);
    }
    expect(message).not.toBe("");
    expect(message).not.toContain("TOPSECRETMATERIAL");
  });

  it("rejects an empty key id or issuer id", () => {
    expect(() => createToken({ ...BASE, keyId: "", privateKey: privatePem, now: 1 })).toThrow(/key id/i);
    expect(() => createToken({ ...BASE, issuerId: " ", privateKey: privatePem, now: 1 })).toThrow(/issuer/i);
  });
});

describe("normalizePrivateKey (ASC_API_KEY_P8 is base64 of the .p8, same as ios.yml)", () => {
  const { privatePem } = testKeyPair();

  it("decodes a base64-encoded PEM", () => {
    const b64 = Buffer.from(privatePem, "utf8").toString("base64");
    expect(normalizePrivateKey(b64)).toBe(privatePem);
  });

  it("tolerates line-wrapped base64 and surrounding whitespace (as `base64` on Linux emits)", () => {
    const b64 = Buffer.from(privatePem, "utf8").toString("base64");
    const wrapped = (b64.match(/.{1,64}/g) ?? []).join("\n");
    expect(normalizePrivateKey(`\n${wrapped}\n`)).toBe(privatePem);
  });

  it("passes a raw PEM through unchanged", () => {
    expect(normalizePrivateKey(privatePem)).toBe(privatePem);
  });

  it("rejects input that is neither, without echoing it", () => {
    let message = "";
    try {
      normalizePrivateKey("not-a-key-SENTINEL");
    } catch (e) {
      message = String((e as Error).message);
    }
    expect(message).toMatch(/ASC_API_KEY_P8/);
    expect(message).not.toContain("SENTINEL");
  });

  it("rejects empty input", () => {
    expect(() => normalizePrivateKey("  ")).toThrow(/ASC_API_KEY_P8/);
  });
});

describe("createTokenProvider", () => {
  const { privatePem } = testKeyPair();

  it("reuses the token while it is fresh and mints a new one before expiry", () => {
    let now = 1_000_000;
    const provider = createTokenProvider({ ...BASE, privateKey: privatePem, clock: () => now });
    const t1 = provider();
    now += 60;
    expect(provider()).toBe(t1);
    now += 15 * 60; // 16 minutes in: inside the refresh margin of a 15 minute token
    const t2 = provider();
    expect(t2).not.toBe(t1);
    const claims = b64urlJson(t2.split(".")[1]!) as { iat: number; exp: number };
    expect(claims.iat).toBe(now);
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(20 * 60);
  });

  it("announces every minted token through onMint (so it can be masked), and only when it mints", () => {
    let now = 1_000_000;
    const minted: string[] = [];
    const provider = createTokenProvider({ ...BASE, privateKey: privatePem, clock: () => now, onMint: (t) => minted.push(t) });
    const t1 = provider();
    provider();
    expect(minted).toEqual([t1]);
    now += 16 * 60;
    const t2 = provider();
    expect(minted).toEqual([t1, t2]);
  });
});
