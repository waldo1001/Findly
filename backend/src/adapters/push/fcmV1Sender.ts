// specs/001 §8 — FCM HTTP v1 send adapter. Thin: builds the concrete FCM v1 request from a
// PushMessage, exchanges the runtime-only FCM_SERVICE_ACCOUNT_JSON credential for a short-lived
// OAuth2 access token (scope firebase.messaging), and POSTs to
// https://fcm.googleapis.com/v1/projects/<project>/messages:send. Excluded from mutation
// (src/adapters/**) and has no unit tests (thin integration surface, per backend/README.md) —
// the credential is read from the environment at call time, never logged, never committed.
//
// B4 built §8.1 LOCATE_REQUEST. B5 added §8.2 GEOFENCE_EVENT (notification + data) and §8.4
// GEOFENCE_CONFIG_CHANGED (data-only). B24 closed the §8.3 SETTINGS_CHANGED gap left open by
// B4/B5 — src/domain/device/patchDeviceSettings.ts already called pushSender.send() for it
// (best-effort, failure swallowed there), but buildFcmBody's default case threw for any type
// it didn't recognize, so every SETTINGS_CHANGED push silently failed until now.

import { importPKCS8, SignJWT } from "jose";
import type { PushMessage, PushSendOutcome, PushSender } from "../../ports/pushSender";

interface ServiceAccountJson {
  project_id: string;
  client_email: string;
  private_key: string;
}

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const TOKEN_TTL_SECONDS = 3600;
const TOKEN_REFRESH_SKEW_MS = 60_000; // refresh a minute before the cached token actually expires

let cachedServiceAccount: ServiceAccountJson | undefined;
let cachedAccessToken: { token: string; expiresAtMs: number } | undefined;

function loadServiceAccount(): ServiceAccountJson {
  if (cachedServiceAccount) return cachedServiceAccount;
  const raw = process.env.FCM_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON app setting is required");
  }
  let parsed: Partial<ServiceAccountJson>;
  try {
    parsed = JSON.parse(raw) as Partial<ServiceAccountJson>;
  } catch {
    // Never include `raw` in the thrown error — it's the credential itself.
    throw new Error("FCM_SERVICE_ACCOUNT_JSON is not valid JSON");
  }
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error("FCM_SERVICE_ACCOUNT_JSON is missing required fields");
  }
  cachedServiceAccount = parsed as ServiceAccountJson;
  return cachedServiceAccount;
}

async function getAccessToken(serviceAccount: ServiceAccountJson): Promise<string> {
  const nowMs = Date.now();
  if (cachedAccessToken && cachedAccessToken.expiresAtMs - TOKEN_REFRESH_SKEW_MS > nowMs) {
    return cachedAccessToken.token;
  }

  const privateKey = await importPKCS8(serviceAccount.private_key, "RS256");
  const nowSec = Math.floor(nowMs / 1000);
  const assertion = await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience(TOKEN_URL)
    .setIssuedAt(nowSec)
    .setExpirationTime(nowSec + TOKEN_TTL_SECONDS)
    .sign(privateKey);

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    // Log the HTTP status only — never the assertion or the response body.
    throw new Error(`FCM OAuth2 token exchange failed: HTTP ${response.status}`);
  }

  const json = (await response.json()) as { access_token: string; expires_in?: number };
  cachedAccessToken = {
    token: json.access_token,
    expiresAtMs: nowMs + (json.expires_in ?? TOKEN_TTL_SECONDS) * 1000,
  };
  return cachedAccessToken.token;
}

function buildLocateRequestBody(message: PushMessage): Record<string, unknown> {
  // specs/001 §8.1 — exact LOCATE_REQUEST shape: high-priority Android, background APNs push.
  return {
    message: {
      token: message.token,
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "5", "apns-push-type": "background" },
        payload: { aps: { "content-available": 1 } },
      },
      data: message.data,
    },
  };
}

function buildGeofenceEventBody(message: PushMessage): Record<string, unknown> {
  // specs/001 §8.2 — notification + data: server-composed English title, no body (the
  // notification's own timestamp conveys the time in the recipient's locale/zone).
  // mutable-content:1 lets an iOS Notification Service Extension re-render the alert locally.
  return {
    message: {
      token: message.token,
      notification: { title: message.notificationTitle },
      android: { priority: "normal" },
      apns: {
        headers: { "apns-priority": "5", "apns-push-type": "alert" },
        payload: { aps: { "mutable-content": 1 } },
      },
      data: message.data,
    },
  };
}

function buildGeofenceConfigChangedBody(message: PushMessage): Record<string, unknown> {
  // specs/001 §8.4 — data-only, normal priority; device responds with GET /geofences
  // (If-None-Match) and re-registers platform geofences.
  return {
    message: {
      token: message.token,
      android: { priority: "normal" },
      apns: {
        headers: { "apns-priority": "5", "apns-push-type": "background" },
        payload: { aps: { "content-available": 1 } },
      },
      data: message.data,
    },
  };
}

function buildSettingsChangedBody(message: PushMessage): Record<string, unknown> {
  // specs/001 §8.3 — data-only, normal priority; carries the complete current values of both
  // fields (full state, never a delta), so the device can apply immediately regardless of
  // reorder. Best-effort: the guaranteed pickup paths are the §5.1 piggyback/settings poll.
  return {
    message: {
      token: message.token,
      android: { priority: "normal" },
      apns: {
        headers: { "apns-priority": "5", "apns-push-type": "background" },
        payload: { aps: { "content-available": 1 } },
      },
      data: message.data,
    },
  };
}

function buildFcmBody(message: PushMessage): Record<string, unknown> {
  switch (message.type) {
    case "LOCATE_REQUEST":
      return buildLocateRequestBody(message);
    case "GEOFENCE_EVENT":
      return buildGeofenceEventBody(message);
    case "SETTINGS_CHANGED":
      return buildSettingsChangedBody(message);
    case "GEOFENCE_CONFIG_CHANGED":
      return buildGeofenceConfigChangedBody(message);
    default:
      throw new Error(`fcmV1Sender: unknown push message type "${message.type}"`);
  }
}

/**
 * FCM v1 error responses use the google.rpc.Status shape:
 * { error: { code, message, status, details: [{ "@type": "...FcmError", errorCode }] } }
 * (specs/001 §8.5 — UNREGISTERED / INVALID_ARGUMENT on the token).
 */
function isInvalidTokenError(body: unknown): boolean {
  if (typeof body !== "object" || body === null) return false;
  const error = (body as { error?: { details?: unknown[] } }).error;
  const details = error && Array.isArray(error.details) ? error.details : [];
  return details.some((detail) => {
    if (typeof detail !== "object" || detail === null) return false;
    const errorCode = (detail as { errorCode?: string }).errorCode;
    return errorCode === "UNREGISTERED" || errorCode === "INVALID_ARGUMENT";
  });
}

export class FcmV1Sender implements PushSender {
  async send(message: PushMessage): Promise<PushSendOutcome> {
    const serviceAccount = loadServiceAccount();
    const accessToken = await getAccessToken(serviceAccount);
    const url = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json; charset=utf-8",
      },
      body: JSON.stringify(buildFcmBody(message)),
    });

    if (response.ok) {
      return "ok";
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      body = undefined;
    }

    if (response.status === 404 || isInvalidTokenError(body)) {
      return "invalidToken";
    }

    return "error";
  }
}
