// specs/005 §2.2 — group state is a pure function, never a stored column: no transition
// writes, no drift. `expired` is never serialized in a response (001 §12); callers filter
// it (list, §12.2) or map it to 410 GROUP_EXPIRED (get/join, §12.3/§12.6).

import type { GroupExpiryPolicy } from "../../ports/repositories";

export type GroupState = "active" | "ended" | "archived" | "expired";

/**
 * state(now, endsAt, policy):
 *   endsAt = null                                 -> "active"   (no end date, 005 §2.5)
 *   now < endsAt                                 -> "active"
 *   policy = delete,  now >= endsAt               -> expired
 *   policy = grace,   endsAt <= now < graceUntil  -> "ended"    (owner may reactivate)
 *   policy = grace,   now >= graceUntil           -> expired
 *   policy = archive, now >= endsAt               -> "archived"
 *
 * graceUntil = endsAt + groupGraceDays (005 §2.2) — resolved from the caller's own
 * features.limits.groupGraceDays at call sites in this task (create/list/get/join), since
 * 002 §2.2's list cost model is explicitly "reverse-index scan + Groups.meta point-reads
 * only" (no extra owner-entitlement reads); `maxGroupMembers` remains the one owner-plan
 * exception, per 001 §9.
 */
/** `endsAt + groupGraceDays`, in epoch ms — the instant a `grace`-policy group flips from
 * `ended` to `expired` (005 §2.2). Exported so the sweeper (B12, 002 §4.1 step 4) can compute
 * the re-bucket target date without duplicating this arithmetic. */
export function graceUntilMs(endsAt: string, groupGraceDays: number): number {
  return new Date(endsAt).getTime() + groupGraceDays * 24 * 60 * 60 * 1000;
}

export function deriveGroupState(
  now: Date,
  endsAt: string | null,
  policy: GroupExpiryPolicy,
  groupGraceDays: number,
): GroupState {
  if (endsAt === null) {
    return "active"; // no end date (005 §2.5) — never ended/archived/expired by itself
  }

  const endsAtMs = new Date(endsAt).getTime();
  const nowMs = now.getTime();

  if (nowMs < endsAtMs) {
    return "active";
  }

  if (policy === "archive") {
    return "archived";
  }

  if (policy === "delete") {
    return "expired";
  }

  // policy === "grace"
  return nowMs < graceUntilMs(endsAt, groupGraceDays) ? "ended" : "expired";
}
