// specs/011 §4.2, 002 §4.3 — the stale nudger: the project's second timer-triggered function
// (the group sweeper, 002 §4.1, is the precedent). Every 30 minutes. Thin: build deps ->
// domain -> log counts. No business logic here (excluded from mutation). Gated by the
// STALE_NUDGE_ENABLED app setting (sends only when exactly "true"). Logs COUNTS ONLY — never
// deviceId, user ids, tokens or names (docs/security-review-checklist.md timer-function note).

import { app, type InvocationContext, type Timer } from "@azure/functions";
import { runStaleNudge } from "../domain/device/staleNudge";
import { toSafeErrorLog } from "../http/errorLogging";
import { TableDeviceRepo } from "../adapters/tables/devicesTableRepo";
import { FcmV1Sender } from "../adapters/push/fcmV1Sender";
import { SystemClock } from "../adapters/support/systemClock";

const deviceRepo = new TableDeviceRepo();
const pushSender = new FcmV1Sender();
const clock = new SystemClock();

app.timer("staleNudger", {
  // NCRONTAB: {second} {minute} {hour} {day} {month} {day-of-week} — every 30 minutes.
  schedule: "0 */30 * * * *",
  handler: async (_myTimer: Timer, context: InvocationContext): Promise<void> => {
    try {
      const result = await runStaleNudge({
        deviceRepo,
        pushSender,
        clock,
        enabledSetting: process.env.STALE_NUDGE_ENABLED,
      });
      context.log(
        `staleNudger: enabled=${result.enabled} evaluated=${result.evaluated} due=${result.due} ` +
          `sent=${result.sent} failed=${result.failed}`,
      );
    } catch (err) {
      context.error("staleNudger: unhandled error", toSafeErrorLog(err));
    }
  },
});
