// specs/001 §8.1–§8.4 — pure FCM v1 message body builders for the four push message shapes.
// Lifted out of src/adapters/push/fcmV1Sender.ts (B27): that adapter is excluded from
// mutation (src/adapters/**, per backend/README.md) and had no unit tests, which is exactly
// how B24's silent SETTINGS_CHANGED gap survived — buildFcmBody's default case threw for a
// type it didn't recognize, so every settings push failed silently until someone noticed.
// Living in src/domain now puts these four shapes under the mutation gate.
//
// PURE: no process.env, no fetch, no jose, no Azure/Google imports. The adapter
// (src/adapters/push/fcmV1Sender.ts) stays the thin credential-and-transport shell that
// imports buildFcmBody from here.

import type { PushMessage } from "../../ports/pushSender";

function buildLocateRequestBody(message: PushMessage): Record<string, unknown> {
  // specs/001 §8.1 (amended 2026-09-06) — user-visible on both platforms.
  // Android stays DATA-ONLY at high priority: the client posts its own notification
  // (specs/009 §5.1) — an FCM `notification` block would make the SDK display it and skip
  // onMessageReceived for a backgrounded app.
  // iOS becomes an alert push: apns-push-type alert, apns-priority 10, aps.alert.title
  // server-composed (message.notificationTitle, built by the caller — src/domain/locate/
  // createLocateRequest.ts — from data.requestedByName), sound "default", PLUS
  // content-available:1 so the background handler still runs even when the user doesn't tap.
  return {
    message: {
      token: message.token,
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "10", "apns-push-type": "alert" },
        payload: {
          aps: {
            alert: { title: message.notificationTitle },
            sound: "default",
            "content-available": 1,
          },
        },
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

function buildDataOnlyBackgroundBody(message: PushMessage): Record<string, unknown> {
  // specs/001 §8.3 SETTINGS_CHANGED and §8.4 GEOFENCE_CONFIG_CHANGED share this exact wire
  // shape — data-only, normal priority, background APNs push-type — so one function backs
  // both switch cases below rather than two byte-identical ones (two identical functions
  // dispatched separately produced an unkillable mutation-testing gap: a mutant collapsing
  // the SETTINGS_CHANGED case into a fallthrough onto GEOFENCE_CONFIG_CHANGED's identical
  // body was behaviorally equivalent and could never be caught by any assertion on shape).
  // §8.3: carries the complete current values of both settings fields (full state, never a
  // delta), so the device can apply immediately regardless of reorder; best-effort, the
  // guaranteed pickup paths are the §5.1 piggyback/settings poll. §8.4: device responds with
  // GET /geofences (If-None-Match) and re-registers platform geofences.
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

export function buildFcmBody(message: PushMessage): Record<string, unknown> {
  switch (message.type) {
    case "LOCATE_REQUEST":
      return buildLocateRequestBody(message);
    case "GEOFENCE_EVENT":
      return buildGeofenceEventBody(message);
    case "SETTINGS_CHANGED":
    case "GEOFENCE_CONFIG_CHANGED":
      return buildDataOnlyBackgroundBody(message);
    default:
      throw new Error(`fcmMessageBodies: unknown push message type "${message.type}"`);
  }
}
