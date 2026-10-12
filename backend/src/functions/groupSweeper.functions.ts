// specs/002 §4.1 — the group sweeper: the project's first timer-triggered function. Daily,
// off-peak UTC (chosen: 03:00 UTC — low-traffic hour for the SMS-allowlisted region, BE/NL/
// FR/DE/LU, docs/azure-setup.md §3). Thin: build deps -> domain -> log a summary. No business
// logic here (excluded from mutation, no unit tests — integration tests exercise the real
// adapters). Takes no input and logs no location payloads (docs/security-review-checklist.md
// timer-function note) — only group ids and counts, which carry no position/PII data.

import { app, type InvocationContext, type Timer } from "@azure/functions";
import { sweepGroups } from "../domain/group/groupSweeper";
import { toSafeErrorLog } from "../http/errorLogging";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableGroupRepo } from "../adapters/tables/groupsTableRepo";
import { TableGroupCodeRepo } from "../adapters/tables/groupCodesTableRepo";
import { TableGroupExpiryRepo } from "../adapters/tables/groupExpiryTableRepo";
import { TableGroupLastKnownRepo } from "../adapters/tables/groupLastKnownTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { SystemClock } from "../adapters/support/systemClock";

const userRepo = new TableUserRepo();
const groupRepo = new TableGroupRepo();
const groupCodeRepo = new TableGroupCodeRepo();
const groupExpiryRepo = new TableGroupExpiryRepo();
const groupLastKnownRepo = new TableGroupLastKnownRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const clock = new SystemClock();

app.timer("groupSweeper", {
  // NCRONTAB: {second} {minute} {hour} {day} {month} {day-of-week} — daily at 03:00 UTC.
  schedule: "0 0 3 * * *",
  handler: async (_myTimer: Timer, context: InvocationContext): Promise<void> => {
    try {
      const result = await sweepGroups({
        groupExpiryRepo,
        groupRepo,
        groupCodeRepo,
        groupLastKnownRepo,
        userRepo,
        entitlementsRepo,
        clock,
      });
      context.log(
        `groupSweeper: scanned ${result.scannedBuckets} buckets / ${result.rowsScanned} rows — ` +
          `hardDeleted=${result.hardDeleted.length} graceTransitioned=${result.graceTransitioned.length} ` +
          `archived=${result.archived.length} rebucketed=${result.rebucketed.length} ` +
          `orphansCleaned=${result.orphansCleaned.length} staleRowsRemoved=${result.staleRowsRemoved.length} skipped=${result.skipped.length} ` +
          `errors=${result.errors.length}`,
      );
      if (result.errors.length > 0) {
        // groupId + message only — never location data (there is none in a GroupExpiry row
        // or Groups.meta to begin with).
        context.error("groupSweeper: per-row failures (retried on next scheduled run)", result.errors);
      }
    } catch (err) {
      context.error("groupSweeper: unhandled error", toSafeErrorLog(err));
    }
  },
});
