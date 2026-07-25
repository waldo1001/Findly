// specs/002 §3.1/§3.2/§3.3 `history`/`events` containers. Append side (POST /locations,
// POST /geofence-events) plus the B6 read side (GET /locations/history, GET
// /geofence-events): day-blob walk + cursor resume. Integration-tested against Azurite
// (test/integration/); no unit tests here (thin adapter, excluded from mutation) — the
// pure day-walk/cursor logic that IS mutation-tested lives in src/domain/history/.

import { RestError, type ContainerClient } from "@azure/storage-blob";
import { createContainerClient } from "./blobClientFactory";
import {
  decodeEventCursor,
  decodeFixCursor,
  encodeEventCursor,
  encodeFixCursor,
  type EventCursor,
  type FixCursor,
} from "../../domain/history/cursor";
import type { EventLine, FixLine, HistoryPage, HistoryStore } from "../../ports/historyStore";

function isAlreadyExists(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 409;
}

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

/** UTC yyyy/MM/dd path segments from an ISO 8601 `recordedAt` (002 §3.1 day-boundary rule). */
function dayPath(recordedAtIso: string): string {
  const date = new Date(recordedAtIso);
  const yyyy = String(date.getUTCFullYear());
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  return `${yyyy}/${mm}/${dd}`;
}

/** Same yyyy/MM/dd path segments, but from a plain "YYYY-MM-DD" query param. */
function dayPathFromDateString(dateStr: string): string {
  const [yyyy, mm, dd] = dateStr.split("-");
  return `${yyyy}/${mm}/${dd}`;
}

/** Ascending "YYYY-MM-DD" UTC calendar dates from `from` to `to`, inclusive. */
function utcDaysBetween(from: string, to: string): string[] {
  const days: string[] = [];
  let cur = Date.parse(`${from}T00:00:00Z`);
  const end = Date.parse(`${to}T00:00:00Z`);
  while (cur <= end) {
    days.push(new Date(cur).toISOString().slice(0, 10));
    cur += 86_400_000;
  }
  return days;
}

/** Byte length of a line exactly as it is written by appendLine (line + "\n"). */
function serializedLength(value: unknown): number {
  return Buffer.byteLength(`${JSON.stringify(value)}\n`, "utf-8");
}

async function appendLine(container: ContainerClient, blobPath: string, line: unknown): Promise<void> {
  const client = container.getAppendBlobClient(blobPath);
  try {
    await client.create({ conditions: { ifNoneMatch: "*" } });
  } catch (err) {
    if (!isAlreadyExists(err)) throw err;
  }
  const buffer = Buffer.from(`${JSON.stringify(line)}\n`, "utf-8");
  await client.appendBlock(buffer, buffer.length);
}

/** Downloads a day blob's full content and splits it into non-empty JSONL lines. Missing
 * blob (no data that day) resolves to an empty array rather than throwing. */
async function downloadDayLines(container: ContainerClient, blobPath: string): Promise<string[]> {
  const client = container.getAppendBlobClient(blobPath);
  try {
    const buffer = await client.downloadToBuffer();
    return buffer
      .toString("utf-8")
      .split("\n")
      .filter((line) => line.length > 0);
  } catch (err) {
    if (isNotFound(err)) return [];
    throw err;
  }
}

/** One-level "directory" listing under `{familyId}/{userId}/` = the set of deviceIds that
 * have ever written history for that user (002 §3.1 path shape). */
async function listDeviceIds(container: ContainerClient, familyId: string, userId: string): Promise<string[]> {
  const prefix = `${familyId}/${userId}/`;
  const deviceIds: string[] = [];
  for await (const item of container.listBlobsByHierarchy("/", { prefix })) {
    if (item.kind === "prefix") {
      deviceIds.push(item.name.slice(prefix.length, -1));
    }
  }
  return deviceIds.sort();
}

/** Deletes every blob under `prefix` in `container` (`deleteIfExists` is itself
 * not-found-tolerant, so no try/catch is needed here — 002 §4.2 idempotency idiom). */
async function deletePrefix(container: ContainerClient, prefix: string): Promise<void> {
  for await (const blob of container.listBlobsFlat({ prefix })) {
    await container.getBlobClient(blob.name).deleteIfExists();
  }
}

export class BlobHistoryStore implements HistoryStore {
  private readonly historyContainer = createContainerClient("history");
  private readonly eventsContainer = createContainerClient("events");

  async appendFix(familyId: string, userId: string, deviceId: string, fix: FixLine): Promise<void> {
    const blobPath = `${familyId}/${userId}/${deviceId}/${dayPath(fix.recordedAt)}.jsonl`;
    await appendLine(this.historyContainer, blobPath, fix);
  }

  async appendEvent(familyId: string, event: EventLine): Promise<void> {
    const blobPath = `${familyId}/${dayPath(event.recordedAt)}.jsonl`;
    await appendLine(this.eventsContainer, blobPath, event);
  }

  /**
   * Walks history/{familyId}/{userId}/{deviceId}/{yyyy}/{MM}/{dd}.jsonl day blobs ascending
   * from `from` to `to` (002 §3.3): merges every relevant device (or just `deviceId` when
   * given), dedupes duplicate fixIds per day (last write wins by receivedAt), sorts by
   * recordedAt, and fills up to `limit`. The resume cursor's "byte offset" is measured
   * against each device's own canonical (sorted+deduped) re-serialization for that day —
   * not raw physical file position — so resuming stays correct even though concurrent
   * AppendBlock calls (002 §3.2) can leave a device's lines physically out of time order.
   */
  async readFixHistory(
    familyId: string,
    userId: string,
    deviceId: string | undefined,
    from: string,
    to: string,
    limit: number,
    cursor: string | null,
  ): Promise<HistoryPage<FixLine & { deviceId: string }>> {
    const resume: FixCursor = cursor ? decodeFixCursor(cursor) : { d: from, o: {} };
    const days = utcDaysBetween(from, to).filter((d) => d >= resume.d);
    const deviceIds = deviceId ? [deviceId] : await listDeviceIds(this.historyContainer, familyId, userId);

    const results: (FixLine & { deviceId: string })[] = [];
    let nextCursor: string | null = null;

    for (const day of days) {
      if (results.length >= limit) {
        nextCursor = encodeFixCursor({ d: day, o: {} });
        break;
      }

      const candidates: { deviceId: string; fix: FixLine; cumBytes: number }[] = [];

      for (const dId of deviceIds) {
        const blobPath = `${familyId}/${userId}/${dId}/${dayPathFromDateString(day)}.jsonl`;
        const lines = await downloadDayLines(this.historyContainer, blobPath);
        if (lines.length === 0) continue;

        const byFixId = new Map<string, FixLine>();
        for (const line of lines) {
          const fix = JSON.parse(line) as FixLine;
          const existing = byFixId.get(fix.fixId);
          if (!existing || Date.parse(fix.receivedAt) >= Date.parse(existing.receivedAt)) {
            byFixId.set(fix.fixId, fix);
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

  /**
   * Walks events/{familyId}/{yyyy}/{MM}/{dd}.jsonl day blobs ascending from `from` to `to`
   * (002 §3.3): one blob per family/day already interleaves every device/user, so this
   * filters by the optional `userId`, dedupes by eventId (last write wins by receivedAt),
   * sorts by recordedAt, and fills up to `limit`.
   */
  async readEventHistory(
    familyId: string,
    from: string,
    to: string,
    userId: string | undefined,
    limit: number,
    cursor: string | null,
  ): Promise<HistoryPage<EventLine>> {
    const resume: EventCursor = cursor ? decodeEventCursor(cursor) : { d: from, o: 0 };
    const days = utcDaysBetween(from, to).filter((d) => d >= resume.d);

    const results: EventLine[] = [];
    let nextCursor: string | null = null;

    for (const day of days) {
      if (results.length >= limit) {
        nextCursor = encodeEventCursor({ d: day, o: 0 });
        break;
      }

      const blobPath = `${familyId}/${dayPathFromDateString(day)}.jsonl`;
      const lines = await downloadDayLines(this.eventsContainer, blobPath);

      const byEventId = new Map<string, EventLine>();
      for (const line of lines) {
        const event = JSON.parse(line) as EventLine;
        const existing = byEventId.get(event.eventId);
        if (!existing || Date.parse(event.receivedAt) >= Date.parse(existing.receivedAt)) {
          byEventId.set(event.eventId, event);
        }
      }
      const filtered = userId
        ? [...byEventId.values()].filter((event) => event.userId === userId)
        : [...byEventId.values()];
      const sorted = filtered.sort((a, b) => {
        const t = Date.parse(a.recordedAt) - Date.parse(b.recordedAt);
        return t !== 0 ? t : a.eventId.localeCompare(b.eventId);
      });

      const startOffset = day === resume.d ? resume.o : 0;
      const candidates: { event: EventLine; cumBytes: number }[] = [];
      let cum = 0;
      for (const event of sorted) {
        cum += serializedLength(event);
        if (cum > startOffset) candidates.push({ event, cumBytes: cum });
      }

      const remaining = limit - results.length;
      const emitted = candidates.slice(0, remaining);
      results.push(...emitted.map((c) => c.event));

      if (emitted.length < candidates.length) {
        const lastCum = emitted.length > 0 ? emitted[emitted.length - 1]!.cumBytes : startOffset;
        nextCursor = encodeEventCursor({ d: day, o: lastCum });
        break;
      }
    }

    return { items: results, nextCursor };
  }

  /** Wipes the whole `history/{familyId}/` and `events/{familyId}/` blob prefixes — family
   * deletion (001 §13.3, 002 §4.2 step 4, B19). Idempotent. */
  async deleteFamilyPrefix(familyId: string): Promise<void> {
    await deletePrefix(this.historyContainer, `${familyId}/`);
    await deletePrefix(this.eventsContainer, `${familyId}/`);
  }
}
