// specs/001 §8.1–§8.4 — field-for-field coverage of the four FCM v1 push message body
// shapes, lifted out of the (mutation-excluded, untested) src/adapters/push/fcmV1Sender.ts
// into src/domain/push/fcmMessageBodies.ts (B27). This is exactly the coverage gap that let
// B24's SETTINGS_CHANGED default-case throw survive silently.

import { describe, expect, it } from "vitest";
import { buildFcmBody } from "../../../src/domain/push/fcmMessageBodies";
import type { PushMessage, PushMessageType } from "../../../src/ports/pushSender";

describe("fcmMessageBodies / buildFcmBody", () => {
  it("LOCATE_REQUEST — specs/001 §8.1 (amended 2026-09-06): Android data-only high priority; iOS alert + content-available", () => {
    const message: PushMessage = {
      token: "device-token-1",
      type: "LOCATE_REQUEST",
      notificationTitle: "Eric is locating you",
      data: {
        type: "LOCATE_REQUEST",
        requestId: "lr_abc",
        requestedByName: "Eric",
        expiresAt: "2026-07-19T09:08:12Z",
      },
    };

    expect(buildFcmBody(message)).toEqual({
      message: {
        token: "device-token-1",
        android: { priority: "high" },
        apns: {
          headers: { "apns-priority": "10", "apns-push-type": "alert" },
          payload: {
            aps: {
              alert: { title: "Eric is locating you" },
              sound: "default",
              "content-available": 1,
            },
          },
        },
        data: message.data,
      },
    });
  });

  it("LOCATE_REQUEST body has no top-level `notification` block on Android (data-only, per §8.1)", () => {
    const message: PushMessage = {
      token: "t",
      type: "LOCATE_REQUEST",
      notificationTitle: "X is locating you",
      data: { type: "LOCATE_REQUEST", requestId: "lr_1", requestedByName: "X", expiresAt: "2026-01-01T00:00:00Z" },
    };

    const body = buildFcmBody(message) as { message: Record<string, unknown> };
    expect(body.message.notification).toBeUndefined();
  });

  it("GEOFENCE_EVENT — specs/001 §8.2: notification + data, mutable-content for iOS re-render", () => {
    const message: PushMessage = {
      token: "device-token-2",
      type: "GEOFENCE_EVENT",
      notificationTitle: "Noor arrived at Home",
      data: {
        type: "GEOFENCE_EVENT",
        userId: "u2",
        displayName: "Noor",
        geofenceId: "gf_home",
        geofenceName: "Home",
        transition: "enter",
        recordedAt: "2026-07-19T15:03:22Z",
      },
    };

    expect(buildFcmBody(message)).toEqual({
      message: {
        token: "device-token-2",
        notification: { title: "Noor arrived at Home" },
        android: { priority: "normal" },
        apns: {
          headers: { "apns-priority": "5", "apns-push-type": "alert" },
          payload: { aps: { "mutable-content": 1 } },
        },
        data: message.data,
      },
    });
  });

  it("SETTINGS_CHANGED — specs/001 §8.3: data-only, normal priority, background APNs push-type", () => {
    const message: PushMessage = {
      token: "device-token-3",
      type: "SETTINGS_CHANGED",
      data: { type: "SETTINGS_CHANGED", syncIntervalMinutes: "30", trackingEnabled: "false" },
    };

    expect(buildFcmBody(message)).toEqual({
      message: {
        token: "device-token-3",
        android: { priority: "normal" },
        apns: {
          headers: { "apns-priority": "5", "apns-push-type": "background" },
          payload: { aps: { "content-available": 1 } },
        },
        data: message.data,
      },
    });
  });

  it("GEOFENCE_CONFIG_CHANGED — specs/001 §8.4: data-only, normal priority, background APNs push-type", () => {
    const message: PushMessage = {
      token: "device-token-4",
      type: "GEOFENCE_CONFIG_CHANGED",
      data: { type: "GEOFENCE_CONFIG_CHANGED", etag: '"0x8DC…"' },
    };

    expect(buildFcmBody(message)).toEqual({
      message: {
        token: "device-token-4",
        android: { priority: "normal" },
        apns: {
          headers: { "apns-priority": "5", "apns-push-type": "background" },
          payload: { aps: { "content-available": 1 } },
        },
        data: message.data,
      },
    });
  });

  it("throws for an unrecognized message type (the exact shape of the B24 SETTINGS_CHANGED gap)", () => {
    const message = {
      token: "t",
      type: "SOMETHING_NEW" as unknown as PushMessageType,
      data: {},
    } as PushMessage;

    expect(() => buildFcmBody(message)).toThrow(/unknown push message type/i);
    expect(() => buildFcmBody(message)).toThrow(/SOMETHING_NEW/);
  });
});
