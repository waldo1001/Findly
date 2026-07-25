// specs/002 §4 — physical retention ("delete at 400 d"). specs/008 §3 / specs/001 §13.1 —
// the export reads this FULL physical retention window, deliberately beyond
// features.limits.historyDays (the free-tier read window used by GET /locations/history and
// GET /geofence-events, 001 §5.3/§7.4). Pure, mutation-tested directly.

const RETENTION_DAYS = 400;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

function utcDateString(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * [from, to] UTC calendar-date span covering the full physical retention window, ending
 * today (`now`'s UTC date) — the day-range the export's history/event walk uses (001 §13.1).
 * Unlike the paginated history endpoints (§5.3/§7.4), there is no `historyDays`/31-day-span
 * gate here: export deliberately walks the whole window (008 §3).
 */
export function resolveExportWindow(now: Date): { from: string; to: string } {
  const toMs = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const fromMs = toMs - RETENTION_DAYS * MS_PER_DAY;
  return { from: utcDateString(fromMs), to: utcDateString(toMs) };
}
