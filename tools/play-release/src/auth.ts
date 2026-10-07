// Google service-account auth, dependency-free: a hand-assembled RS256 JWT (node:crypto) traded for
// an OAuth2 access token via the JWT-bearer grant (RFC 7523), exactly what google-auth-library
// does. Hard rule for this file: the service-account JSON, the private key, the signed assertion
// and the access token never appear in a log line or an error message. Parser/crypto errors are
// therefore replaced by fixed messages — Node's own JSON.parse message, for one, quotes the input.

import { createSign } from "node:crypto";

export const PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher";

/**
 * Google's token endpoint — the only place the signed assertion is ever sent. Pinned in code
 * rather than taken from the key file's `token_uri`: a key file is data, and a doctored one must
 * not be able to redirect a freshly signed credential to another host (store-readiness §5).
 */
export const TOKEN_URI = "https://oauth2.googleapis.com/token";

/** Google rejects assertions that live longer than an hour. */
const JWT_LIFETIME_SECONDS = 3600;

export type FetchFn = (url: string, init?: RequestInit) => Promise<Response>;

/** Called with every derived credential (signed assertion, access token) so the caller can mask it in logs. */
export type MaskFn = (secret: string) => void;

export interface ServiceAccount {
  clientEmail: string;
  privateKey: string;
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim() !== "";
}

export function parseServiceAccount(json: string | undefined): ServiceAccount {
  if (json === undefined || json.trim() === "") {
    throw new Error("PLAY_SERVICE_ACCOUNT_JSON is not set or empty.");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    // Deliberately drops the original error: its message quotes a slice of the input.
    throw new Error("PLAY_SERVICE_ACCOUNT_JSON is not valid JSON.");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("PLAY_SERVICE_ACCOUNT_JSON must be a JSON object.");
  }

  const fields = parsed as Record<string, unknown>;
  if (!nonEmptyString(fields.client_email)) {
    throw new Error("Service account JSON has no client_email.");
  }
  if (!nonEmptyString(fields.private_key)) {
    throw new Error("Service account JSON has no private_key.");
  }
  if (fields.token_uri !== undefined && fields.token_uri !== TOKEN_URI) {
    // The offending value is not echoed: it comes from the secret.
    throw new Error(`Service account token_uri is not Google's token endpoint (${TOKEN_URI}); refusing to use this key.`);
  }

  return { clientEmail: fields.client_email, privateKey: fields.private_key };
}

function base64url(value: string | Buffer): string {
  return Buffer.from(value).toString("base64url");
}

export function buildJwt(sa: ServiceAccount, nowSeconds: number): string {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(
    JSON.stringify({
      iss: sa.clientEmail,
      scope: PLAY_SCOPE,
      aud: TOKEN_URI,
      iat: nowSeconds,
      exp: nowSeconds + JWT_LIFETIME_SECONDS,
    }),
  );
  const signingInput = `${header}.${claims}`;

  let signature: Buffer;
  try {
    signature = createSign("RSA-SHA256").update(signingInput).sign(sa.privateKey);
  } catch {
    throw new Error("Could not sign the JWT with the service-account private key.");
  }
  return `${signingInput}.${base64url(signature)}`;
}

function readJson(text: string): Record<string, unknown> | undefined {
  try {
    const value: unknown = JSON.parse(text);
    return typeof value === "object" && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

export async function fetchAccessToken(
  fetchFn: FetchFn,
  sa: ServiceAccount,
  nowSeconds: number,
  mask: MaskFn = () => undefined,
): Promise<string> {
  const assertion = buildJwt(sa, nowSeconds);
  // Registered before the request leaves: from here on, any accidental echo is redacted by the runner.
  mask(assertion);
  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  let response: Response;
  try {
    response = await fetchFn(TOKEN_URI, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: body.toString(),
      signal: AbortSignal.timeout(30_000),
    });
  } catch {
    // The original error is dropped on purpose: it may quote the request (which holds the assertion).
    throw new Error("Could not reach the token endpoint (network error).");
  }

  const payload = readJson(await response.text());

  if (!response.ok) {
    const code = typeof payload?.error === "string" ? payload.error : undefined;
    const description = typeof payload?.error_description === "string" ? payload.error_description : undefined;
    const detail = [code, description].filter(Boolean).join(": ");
    throw new Error(`Token exchange failed (HTTP ${response.status})${detail ? `: ${detail}` : "."}`);
  }

  const token = payload?.access_token;
  if (!nonEmptyString(token)) {
    throw new Error("Token exchange response has no access_token.");
  }
  mask(token);
  return token;
}
