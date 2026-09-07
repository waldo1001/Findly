// FCM HTTP v1 sender (specs/001 §8) — later tasks (B4/B5). Interface only; no fake/adapter yet.

export type PushMessageType =
  | "LOCATE_REQUEST"
  | "GEOFENCE_EVENT"
  | "SETTINGS_CHANGED"
  | "GEOFENCE_CONFIG_CHANGED";

interface PushMessageBase {
  token: string;
  /** FCM data payload — all values MUST be strings (§8 constraint). */
  data: Record<string, string>;
}

/** §8.1 (amended 2026-09-06) — user-visible on both platforms; iOS reads this into
 * `aps.alert.title`. Title is REQUIRED: an alert push with no alert text is exactly the
 * invisible-push failure the 2026-09-06 amendment exists to eliminate (B28). */
export interface LocateRequestPushMessage extends PushMessageBase {
  type: "LOCATE_REQUEST";
  notificationTitle: string;
}

/** §8.2 — notification + data; `notification.title` is server-composed and REQUIRED —
 * this type has carried the same latent hole as LOCATE_REQUEST since it was built (B28). */
export interface GeofenceEventPushMessage extends PushMessageBase {
  type: "GEOFENCE_EVENT";
  notificationTitle: string;
}

/** §8.3 — data-only, normal priority. No notification title: deliberately has no
 * `notificationTitle` field at all (not merely optional) so this type structurally cannot
 * leak a title into a background push (B28). */
export interface SettingsChangedPushMessage extends PushMessageBase {
  type: "SETTINGS_CHANGED";
}

/** §8.4 — data-only, normal priority. Same title-free shape as SETTINGS_CHANGED (B28). */
export interface GeofenceConfigChangedPushMessage extends PushMessageBase {
  type: "GEOFENCE_CONFIG_CHANGED";
}

/**
 * Discriminated union on `type` (B28): `notificationTitle` is a REQUIRED string for the two
 * "alert" shapes (§8.1 LOCATE_REQUEST, §8.2 GEOFENCE_EVENT) and structurally ABSENT — not
 * merely optional — for the two data-only shapes (§8.3 SETTINGS_CHANGED, §8.4
 * GEOFENCE_CONFIG_CHANGED). This makes it a compile error to construct an alert-type
 * message without a title, and a compile error for src/domain/push/fcmMessageBodies.ts's
 * shared data-only builder to read a title that cannot exist on its narrowed parameter type.
 */
export type PushMessage =
  | LocateRequestPushMessage
  | GeofenceEventPushMessage
  | SettingsChangedPushMessage
  | GeofenceConfigChangedPushMessage;

export type PushSendOutcome = "ok" | "invalidToken" | "error";

export interface PushSender {
  /**
   * `invalidToken` MUST cause the caller to mark the device pushInvalid: true (§8.5) —
   * this port intentionally never throws for a rejected token, only for transport failure.
   */
  send(message: PushMessage): Promise<PushSendOutcome>;
}
