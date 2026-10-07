// 002 §4.3 — reconciling a request-path full-row Replace that lost an ETag race (412).
// The stale nudger (and the §4.2 lastSeenAt refresh) write single fields by Merge while a
// request holds a whole-row snapshot; replaying that snapshot over the fresh row would revert
// them (a nudge claim lost -> a second visible push inside 24 h). The caller's intended change
// is kept (it wins every field it owns); only the system-written fields are carried from the
// fresh row. Pure.

import type { DeviceRecord } from "../../ports/repositories";

function later(a: string | undefined, b: string | undefined): string | undefined {
  if (a === undefined) return b;
  if (b === undefined) return a;
  return new Date(a).getTime() >= new Date(b).getTime() ? a : b;
}

/** `fresh` = the row as re-read after the 412; `intended` = the caller's full record. Returns the
 * record to retry with: `intended`, plus fresh's etag and the system-written fields merged. */
export function reconcileStaleReplace(fresh: DeviceRecord, intended: DeviceRecord): DeviceRecord {
  const { lastNudgedAt: _drop, ...rest } = intended;
  const lastNudgedAt = later(fresh.lastNudgedAt, intended.lastNudgedAt);
  return {
    ...rest,
    ...(lastNudgedAt === undefined ? {} : { lastNudgedAt }),
    pushInvalid: fresh.pushInvalid || intended.pushInvalid,
    lastSeenAt: later(fresh.lastSeenAt, intended.lastSeenAt) as string,
    etag: fresh.etag,
  };
}
