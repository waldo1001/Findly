import { createPrivateKey, sign, type KeyObject } from "node:crypto";

/**
 * ES256 JWT for the App Store Connect API
 * (https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests).
 *
 * Header {alg: ES256, kid, typ: JWT}; claims {iss, iat, exp, aud: "appstoreconnect-v1"};
 * lifetime at most 20 minutes (Apple rejects longer for these requests). The signature is the raw
 * 64-byte IEEE P1363 r||s form JWS requires — not Node's default DER.
 *
 * Neither the private key nor a token is ever logged or placed into an error message.
 */

export const MAX_LIFETIME_SECONDS = 20 * 60;
const DEFAULT_LIFETIME_SECONDS = 15 * 60;
const REFRESH_MARGIN_SECONDS = 2 * 60;
const AUDIENCE = "appstoreconnect-v1";

export interface TokenOptions {
  keyId: string;
  issuerId: string;
  /** PEM (PKCS#8, the contents of the `.p8`). Use {@link normalizePrivateKey} on the raw secret. */
  privateKey: string;
  /** Seconds since the epoch; defaults to the current time. */
  now?: number;
  lifetimeSeconds?: number;
}

const b64url = (input: Buffer | string): string => Buffer.from(input).toString("base64url");

function loadKey(pem: string): KeyObject {
  let key: KeyObject;
  try {
    key = createPrivateKey(pem);
  } catch {
    // Deliberately no `cause` and no library message: it can quote parts of the input.
    throw new Error("The App Store Connect private key could not be loaded (expected a PKCS#8 EC P-256 .p8 key).");
  }
  if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
    throw new Error("The App Store Connect private key must be an EC P-256 key (ES256).");
  }
  return key;
}

export function createToken(opts: TokenOptions): string {
  if (opts.keyId.trim() === "") throw new Error("ASC_KEY_ID (key id) must not be empty.");
  if (opts.issuerId.trim() === "") throw new Error("ASC_ISSUER_ID (issuer id) must not be empty.");
  const lifetime = opts.lifetimeSeconds ?? DEFAULT_LIFETIME_SECONDS;
  if (!(lifetime > 0)) throw new Error("Token lifetime must be positive.");
  if (lifetime > MAX_LIFETIME_SECONDS) {
    throw new Error("Token lifetime must not exceed 20 minutes (App Store Connect rejects longer tokens).");
  }
  const key = loadKey(opts.privateKey);
  const iat = opts.now ?? Math.floor(Date.now() / 1000);

  const header = { alg: "ES256", kid: opts.keyId, typ: "JWT" };
  const claims = { iss: opts.issuerId, iat, exp: iat + lifetime, aud: AUDIENCE };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const signature = sign("sha256", Buffer.from(signingInput), { key, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64url(signature)}`;
}

/**
 * `ASC_API_KEY_P8` is stored base64-encoded (docs/store-readiness.md §4, same convention as
 * ios.yml / ANDROID_KEYSTORE_BASE64). Accepts that, or the raw PEM, and returns the PEM.
 * Never echoes the input in the error.
 */
export function normalizePrivateKey(raw: string): string {
  const bad = new Error(
    "ASC_API_KEY_P8 must be the App Store Connect .p8 key: either the PEM text or its base64 encoding.",
  );
  if (raw.trim() === "") throw bad;
  if (raw.includes("-----BEGIN")) return raw;
  // Node's base64 decoder ignores whitespace, so `base64` output wrapped at 76 columns is fine.
  const decoded = Buffer.from(raw, "base64").toString("utf8");
  if (!decoded.includes("-----BEGIN")) throw bad;
  return decoded;
}

export interface TokenProviderOptions extends Omit<TokenOptions, "now"> {
  /** Seconds since the epoch; injectable for tests. */
  clock?: () => number;
}

/** A function returning a valid token, minted lazily and re-minted shortly before expiry. */
export function createTokenProvider(opts: TokenProviderOptions): () => string {
  const clock = opts.clock ?? (() => Math.floor(Date.now() / 1000));
  const lifetime = opts.lifetimeSeconds ?? DEFAULT_LIFETIME_SECONDS;
  let token: string | undefined;
  let expiresAt = 0;
  return () => {
    const now = clock();
    if (token === undefined || now >= expiresAt - REFRESH_MARGIN_SECONDS) {
      token = createToken({ ...opts, now, lifetimeSeconds: lifetime });
      expiresAt = now + lifetime;
    }
    return token;
  };
}
