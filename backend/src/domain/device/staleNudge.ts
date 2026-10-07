// specs/011 §4 — the stale nudge: pure eligibility rule (§4.1) and the per-run orchestration
// (§4.2, 002 §4.3). The timer file (src/functions/staleNudger.functions.ts) stays thin.
// Pure: no Azure/Google imports; time zone handling via the built-in Intl.

import type { DeviceRecord, DeviceRepo } from "../../ports/repositories";
import type { PushSender } from "../../ports/pushSender";
import type { Clock } from "../../ports/support";

/** 011 §4.1 condition 1 — a "presence" device (009 §1.3); 60+ min devices are expected quiet. */
export const NUDGE_MAX_SYNC_INTERVAL_MINUTES = 30;
/** 011 §4.1 condition 4 — flat 2 h (4 × interval ≤ 120 for every interval condition 1 admits). */
export const NUDGE_QUIET_MINUTES = 120;
const NUDGE_GIVE_UP_DAYS = 7;
const NUDGE_RATE_LIMIT_HOURS = 24;
const QUIET_HOURS_ZONE = "Europe/Brussels";
const WINDOW_START_HOUR = 8; // inclusive
const WINDOW_END_HOUR = 21; // exclusive

/** The `STALE_NUDGE_ENABLED` app setting must equal exactly this string for any send. */
export const STALE_NUDGE_ENABLED_VALUE = "true";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

export type NudgeCandidate = Pick<
  DeviceRecord,
  "trackingEnabled" | "syncIntervalMinutes" | "pushToken" | "pushInvalid" | "registeredAt" | "staleNudgeEnabled" | "lastNudgedAt"
> & { lastSeenAt?: string };

const brusselsHour = new Intl.DateTimeFormat("en-GB", {
  timeZone: QUIET_HOURS_ZONE,
  hour: "2-digit",
  hourCycle: "h23",
});

/** Hour of day (0–23) at `instant` in Europe/Brussels, DST-correct via the platform tz database. */
function localHour(instant: Date): number {
  return Number(brusselsHour.format(instant));
}

/** 011 §4.1 — all seven conditions; `now` is the send time. */
export function isNudgeDue(device: NudgeCandidate, now: Date): boolean {
  // 1. presence device
  if (!device.trackingEnabled || device.syncIntervalMinutes > NUDGE_MAX_SYNC_INTERVAL_MINUTES) return false;
  // 2. owner opt-out (absent reads as true — 002 §2.4)
  if (device.staleNudgeEnabled === false) return false;
  // 3. valid push token
  if (!device.pushToken || device.pushInvalid) return false;

  const quietMs = now.getTime() - new Date(device.lastSeenAt ?? device.registeredAt).getTime();
  // 4. quiet strictly longer than 120 min
  if (quietMs <= NUDGE_QUIET_MINUTES * MINUTE_MS) return false;
  // 5. not given up: quiet at most 7 days
  if (quietMs > NUDGE_GIVE_UP_DAYS * DAY_MS) return false;
  // 6. rate limit: at most one per 24 h
  if (
    device.lastNudgedAt !== undefined &&
    now.getTime() - new Date(device.lastNudgedAt).getTime() < NUDGE_RATE_LIMIT_HOURS * HOUR_MS
  ) {
    return false;
  }
  // 7. quiet hours: [08:00, 21:00) Europe/Brussels
  const hour = localHour(now);
  return hour >= WINDOW_START_HOUR && hour < WINDOW_END_HOUR;
}

export interface StaleNudgeDeps {
  deviceRepo: DeviceRepo;
  pushSender: PushSender;
  clock: Clock;
  /** Raw value of the `STALE_NUDGE_ENABLED` app setting. */
  enabledSetting: string | undefined;
}

/** Counts only — the logging invariant (011 §4.2): never ids, tokens or names. */
export interface StaleNudgeResult {
  enabled: boolean;
  evaluated: number;
  due: number;
  sent: number;
  failed: number;
}

export async function runStaleNudge(deps: StaleNudgeDeps): Promise<StaleNudgeResult> {
  if (deps.enabledSetting !== STALE_NUDGE_ENABLED_VALUE) {
    return { enabled: false, evaluated: 0, due: 0, sent: 0, failed: 0 };
  }
  const now = deps.clock.now();
  const devices = await deps.deviceRepo.listAllDevices();
  const result: StaleNudgeResult = { enabled: true, evaluated: devices.length, due: 0, sent: 0, failed: 0 };

  for (const device of devices) {
    if (!isNudgeDue(device, now)) continue;
    result.due += 1;
    try {
      // Claim BEFORE the send (011 §4.2): a crash in between loses one nudge, never duplicates
      // one. Update-only, so a device removed since the scan is neither nudged nor recreated.
      const claimed = await deps.deviceRepo.claimNudge(device.ownerUserId, device.deviceId, now.toISOString());
      if (!claimed) continue;
      const outcome = await deps.pushSender.send({
        type: "STALE_NUDGE",
        // isNudgeDue guarantees a non-empty token.
        token: device.pushToken as string,
        data: { type: "STALE_NUDGE" },
      });
      if (outcome === "ok") {
        result.sent += 1;
        continue;
      }
      if (outcome === "invalidToken") {
        await deps.deviceRepo.markPushInvalid(device.ownerUserId, device.deviceId);
      }
      result.failed += 1;
    } catch {
      // Transport/storage failure on one device never stops the rest; counted, not retried
      // before the next 24 h window (the claim already stands).
      result.failed += 1;
    }
  }
  return result;
}
