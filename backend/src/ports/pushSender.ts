// FCM HTTP v1 sender (specs/001 §8) — later tasks (B4/B5). Interface only; no fake/adapter yet.

export type PushMessageType =
  | "LOCATE_REQUEST"
  | "GEOFENCE_EVENT"
  | "SETTINGS_CHANGED"
  | "GEOFENCE_CONFIG_CHANGED";

export interface PushMessage {
  token: string;
  type: PushMessageType;
  /** FCM data payload — all values MUST be strings (§8 constraint). */
  data: Record<string, string>;
  /** Server-composed notification/alert title (§8's "normative, server-composed" templates).
   * Present for §8.1 LOCATE_REQUEST (iOS `aps.alert.title`, amended 2026-09-06) and §8.2
   * GEOFENCE_EVENT (`notification.title`); absent for the data-only §8.3/§8.4 shapes. */
  notificationTitle?: string;
}

export type PushSendOutcome = "ok" | "invalidToken" | "error";

export interface PushSender {
  /**
   * `invalidToken` MUST cause the caller to mark the device pushInvalid: true (§8.5) —
   * this port intentionally never throws for a rejected token, only for transport failure.
   */
  send(message: PushMessage): Promise<PushSendOutcome>;
}
