import type { EventLine, FixLine, HistoryPage, HistoryStore } from "../../src/ports/historyStore";
import {
  decodeEventCursor,
  decodeFixCursor,
  encodeEventCursor,
  encodeFixCursor,
} from "../../src/domain/history/cursor";

export interface RecordedFix {
  familyId: string;
  userId: string;
  deviceId: string;
  fix: FixLine;
}

interface RecordedEvent {
  familyId: string;
  event: EventLine;
}

function utcDay(dateIso: string): string {
  return dateIso.slice(0, 10);
}

function daysBetween(from: string, to: string): string[] {
  const days: string[] = [];
  let cur = Date.parse(`${from}T00:00:00Z`);
  const end = Date.parse(`${to}T00:00:00Z`);
  while (cur <= end) {
    days.push(new Date(cur).toISOString().slice(0, 10));
    cur += 86_400_000;
  }
  return days;
}

/** Byte length of the line as it would be written to a day blob (002 §3.2), used as the
 * cursor's "byte offset" unit even in this in-memory fake (see historyBlobStore.ts). */
function serializedLength(value: unknown): number {
  return Buffer.byteLength(`${JSON.stringify(value)}\n`, "utf-8");
}

/**
 * In-memory HistoryStore fake (B2 append side; B6 completes the read side). Implements the
 * full 002 §3.3 day-walk + cursor contract — sorted/deduped per day, byte-offset resume,
 * multi-device merge — over an in-memory buffer, so domain unit tests
 * (getLocationHistory/getGeofenceEventHistory) can exercise ascending order, deviceId
 * merge, and cursor round-trip without Azurite. The real adapter is
 * src/adapters/blobs/historyBlobStore.ts.
 */
export class InMemoryHistoryStore implements HistoryStore {
  readonly fixes: RecordedFix[] = [];
  readonly events: RecordedEvent[] = [];

  async appendFix(familyId: string, userId: string, deviceId: string, fix: FixLine): Promise<void> {
    this.fixes.push({ familyId, userId, deviceId, fix: { ...fix } });
  }

  async appendEvent(familyId: string, event: EventLine): Promise<void> {
    this.events.push({ familyId, event: { ...event } });
  }

  async readFixHistory(
    familyId: string,
    userId: string,
    deviceId: string | undefined,
    from: string,
    to: string,
    limit: number,
    cursor: string | null,
  ): Promise<HistoryPage<FixLine & { deviceId: string }>> {
    const resume = cursor ? decodeFixCursor(cursor) : { d: from, o: {} as Record<string, number> };
    const days = daysBetween(from, to).filter((d) => d >= resume.d);

    const deviceIds = deviceId
      ? [deviceId]
      : [
          ...new Set(
            this.fixes
              .filter((r) => r.familyId === familyId && r.userId === userId)
              .map((r) => r.deviceId),
          ),
        ].sort();

    const results: (FixLine & { deviceId: string })[] = [];
    let nextCursor: string | null = null;

    for (const day of days) {
      if (results.length >= limit) {
        nextCursor = encodeFixCursor({ d: day, o: {} });
        break;
      }

      const candidates: { deviceId: string; fix: FixLine; cumBytes: number }[] = [];

      for (const dId of deviceIds) {
        const dayFixes = this.fixes.filter(
          (r) =>
            r.familyId === familyId &&
            r.userId === userId &&
            r.deviceId === dId &&
            utcDay(r.fix.recordedAt) === day,
        );
        if (dayFixes.length === 0) continue;

        const byFixId = new Map<string, FixLine>();
        for (const r of dayFixes) {
          const existing = byFixId.get(r.fix.fixId);
          if (!existing || Date.parse(r.fix.receivedAt) >= Date.parse(existing.receivedAt)) {
            byFixId.set(r.fix.fixId, r.fix);
          }
        }
        const sorted = [...byFixId.values()].sort((a, b) => {
          const t = Date.parse(a.recordedAt) - Date.parse(b.recordedAt);
          return t !== 0 ? t : a.fixId.localeCompare(b.fixId);
        });

        const startOffset = day === resume.d ? (resume.o[dId] ?? 0) : 0;
        let cum = 0;
        for (const fix of sorted) {
          cum += serializedLength(fix);
          if (cum > startOffset) {
            candidates.push({ deviceId: dId, fix, cumBytes: cum });
          }
        }
      }

      candidates.sort((a, b) => {
        const t = Date.parse(a.fix.recordedAt) - Date.parse(b.fix.recordedAt);
        return t !== 0 ? t : a.fix.fixId.localeCompare(b.fix.fixId);
      });

      const remaining = limit - results.length;
      const emitted = candidates.slice(0, remaining);
      for (const c of emitted) {
        results.push({ ...c.fix, deviceId: c.deviceId });
      }

      if (emitted.length < candidates.length) {
        const offsets: Record<string, number> = day === resume.d ? { ...resume.o } : {};
        for (const c of emitted) {
          offsets[c.deviceId] = c.cumBytes;
        }
        nextCursor = encodeFixCursor({ d: day, o: offsets });
        break;
      }
    }

    return { items: results, nextCursor };
  }

  async readEventHistory(
    familyId: string,
    from: string,
    to: string,
    userId: string | undefined,
    limit: number,
    cursor: string | null,
  ): Promise<HistoryPage<EventLine>> {
    const resume = cursor ? decodeEventCursor(cursor) : { d: from, o: 0 };
    const days = daysBetween(from, to).filter((d) => d >= resume.d);

    const results: EventLine[] = [];
    let nextCursor: string | null = null;

    for (const day of days) {
      if (results.length >= limit) {
        nextCursor = encodeEventCursor({ d: day, o: 0 });
        break;
      }

      const dayEvents = this.events
        .filter(
          (r) =>
            r.familyId === familyId &&
            utcDay(r.event.recordedAt) === day &&
            (userId === undefined || r.event.userId === userId),
        )
        .map((r) => r.event);

      const byEventId = new Map<string, EventLine>();
      for (const ev of dayEvents) {
        const existing = byEventId.get(ev.eventId);
        if (!existing || Date.parse(ev.receivedAt) >= Date.parse(existing.receivedAt)) {
          byEventId.set(ev.eventId, ev);
        }
      }
      const sorted = [...byEventId.values()].sort((a, b) => {
        const t = Date.parse(a.recordedAt) - Date.parse(b.recordedAt);
        return t !== 0 ? t : a.eventId.localeCompare(b.eventId);
      });

      const startOffset = day === resume.d ? resume.o : 0;
      const candidates: { ev: EventLine; cumBytes: number }[] = [];
      let cum = 0;
      for (const ev of sorted) {
        cum += serializedLength(ev);
        if (cum > startOffset) candidates.push({ ev, cumBytes: cum });
      }

      const remaining = limit - results.length;
      const emitted = candidates.slice(0, remaining);
      results.push(...emitted.map((c) => c.ev));

      if (emitted.length < candidates.length) {
        const lastCum = emitted.length > 0 ? emitted[emitted.length - 1]!.cumBytes : startOffset;
        nextCursor = encodeEventCursor({ d: day, o: lastCum });
        break;
      }
    }

    return { items: results, nextCursor };
  }

  /** Wipes every recorded fix/event belonging to `familyId` (002 §4.2 step 4, B19). */
  async deleteFamilyPrefix(familyId: string): Promise<void> {
    const keptFixes = this.fixes.filter((r) => r.familyId !== familyId);
    this.fixes.length = 0;
    this.fixes.push(...keptFixes);

    const keptEvents = this.events.filter((r) => r.familyId !== familyId);
    this.events.length = 0;
    this.events.push(...keptEvents);
  }
}
