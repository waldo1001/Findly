// specs/001 §8.8, 011 §4.3 — STALE_NUDGE FCM body, byte-for-byte.
import { describe, expect, it } from "vitest";
import { buildFcmBody } from "../../../src/domain/push/fcmMessageBodies";

describe("fcmMessageBodies / buildFcmBody — STALE_NUDGE (specs/001 §8.8)", () => {
  it("matches the 001 §8.8 wire shape byte-for-byte", () => {
    const body = buildFcmBody({ type: "STALE_NUDGE", token: "tok", data: { type: "STALE_NUDGE" } });
    expect(JSON.stringify(body)).toBe(
      '{"message":{"token":"tok","notification":{"title":"Findly isn\'t sharing your location","body":"Open Findly to start sharing again."},' +
        '"android":{"priority":"normal","notification":{"channel_id":"findly_sharing_status"}},' +
        '"apns":{"headers":{"apns-priority":"5","apns-push-type":"alert"},"payload":{"aps":{"sound":"default"}}},' +
        '"data":{"type":"STALE_NUDGE"}}}',
    );
  });

  it("ignores any extra data the caller passes (no other data, no personal data)", () => {
    const body = buildFcmBody({ type: "STALE_NUDGE", token: "tok", data: { type: "STALE_NUDGE", name: "Eric" } }) as {
      message: { data: unknown };
    };
    expect(body.message.data).toEqual({ type: "STALE_NUDGE" });
  });
});
