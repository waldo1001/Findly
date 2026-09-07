import { expect } from "vitest";
import type { PushMessage } from "../../src/ports/pushSender";

/**
 * Narrows a captured PushMessage to one of the two "alert" variants (§8.1 LOCATE_REQUEST,
 * §8.2 GEOFENCE_EVENT) and asserts its notificationTitle in one call.
 *
 * Exists because PushMessage is a discriminated union (B28): notificationTitle is a
 * required field on the alert variants and does not exist at all on the data-only variants
 * (§8.3 SETTINGS_CHANGED, §8.4 GEOFENCE_CONFIG_CHANGED), so accessing `.notificationTitle`
 * on a bare `PushMessage` no longer compiles without narrowing by `type` first — this is
 * that narrowing, shared across test files instead of repeated per call site.
 */
export function expectNotificationTitle(
  message: PushMessage,
  expectedType: "LOCATE_REQUEST" | "GEOFENCE_EVENT",
  expectedTitle: string,
): void {
  expect(message.type).toBe(expectedType);
  if (message.type !== "LOCATE_REQUEST" && message.type !== "GEOFENCE_EVENT") {
    throw new Error(`expectNotificationTitle: expected an alert-type push, got "${message.type}"`);
  }
  expect(message.notificationTitle).toBe(expectedTitle);
}
