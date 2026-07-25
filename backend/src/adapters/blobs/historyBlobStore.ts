// specs/002 §3.1/§3.2/§3.3 `history`/`events` containers. Append side (POST /locations,
// POST /geofence-events) plus the B6 read side (GET /locations/history, GET
// /geofence-events): day-blob walk + cursor resume. Integration-tested against Azurite
// (test/integration/); no unit tests here (thin adapter, excluded from mutation) — the
// pure day-walk/cursor logic that IS mutation-tested lives in src/domain/history/.

import { RestError, type ContainerClient } from "@azure/storage-blob";
import { createContainerClient } from "./blobClientFactory";
import { collectBlobsTolerant } from "./listTolerant";
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

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 412;
}

/** Node.js readable stream -> Buffer (the SDK's own `downloadToBuffer` doesn't expose the
 * ETag alongside the content; the events filtered rewrite needs both from the SAME GET, so
 * this reads the stream from a raw `.download()` call instead). */
async function streamToBuffer(readable: NodeJS.ReadableStream): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of readable) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as string));
  }
  return Buffer.concat(chunks);
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
  // 002 §4.2 (B20) — a `history` container that has never been created (this subject has no
  // history at all yet) resolves to no device directories, same as an empty prefix.
  const items = await collectBlobsTolerant(container.listBlobsByHierarchy("/", { prefix }));
  const deviceIds = items
    .filter((item) => item.kind === "prefix")
    .map((item) => item.name.slice(prefix.length, -1));
  return deviceIds.sort();
}

// 002 §4.2 "Bounding and the retry contract" — erasure walks are unbounded in principle
// (history spans up to the full retention per device; the events rewrite inspects every
// events/{familyId}/ day-blob for the family's lifetime), so these MUST run with bounded
// parallelism rather than one-at-a-time sequential round-trips, or a long-lived family risks
// the Functions request timeout. Not unbounded Promise.all either — that would open one
// connection per blob at once, which for a very large family could itself exhaust resources.
const ERASURE_CONCURRENCY = 16;

/** Runs `fn` over `items` with at most `concurrency` in flight at once — a plain worker-pool
 * (no external dependency): each of `concurrency` workers pulls the next item off a shared
 * cursor until the list is exhausted. A single item's rejection propagates (via `Promise.all`
 * on the workers), same fail-fast behavior as a sequential loop would have had. */
async function mapWithConcurrency<T>(items: T[], concurrency: number, fn: (item: T) => Promise<void>): Promise<void> {
  let cursor = 0;
  async function worker(): Promise<void> {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      await fn(items[index] as T);
    }
  }
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, () => worker());
  await Promise.all(workers);
}

/** Deletes every blob under `prefix` in `container` (`deleteIfExists` is itself
 * not-found-tolerant, so no try/catch is needed for the per-blob delete — 002 §4.2
 * idempotency idiom). The LISTING itself also tolerates the container never having been
 * created at all (ContainerNotFound, B20) — resolving to nothing to delete, exactly like an
 * existing-but-empty prefix. Bounded-parallel (002 §4.2) — a family's full history/events
 * prefix can span thousands of day blobs across every member/device. */
async function deletePrefix(container: ContainerClient, prefix: string): Promise<void> {
  const blobs = await collectBlobsTolerant(container.listBlobsFlat({ prefix }));
  await mapWithConcurrency(blobs, ERASURE_CONCURRENCY, async (blob) => {
    await container.getBlobClient(blob.name).deleteIfExists();
  });
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

  /** Wipes only the `history/{familyId}/{userId}/` prefix — account deletion's non-cascade
   * path (001 §13.2, 002 §4.2 step 6, B18). Idempotent. */
  async deleteUserPrefix(familyId: string, userId: string): Promise<void> {
    await deletePrefix(this.historyContainer, `${familyId}/${userId}/`);
  }

  /** The interleaved-events filtered rewrite (001 §13.2, 008 §4.3, 002 §4.2): walks every
   * `events/{familyId}/{yyyy}/{MM}/{dd}.jsonl` day blob and erases only the subject's own
   * lines, leaving every other member's lines byte-identical. */
  async eraseUserFromEvents(familyId: string, userId: string): Promise<void> {
    const prefix = `${familyId}/`;
    // 002 §4.2 (B20) — an `events` container that has never been created (this family never
    // had a geofence event) resolves to no day blobs to inspect.
    const blobs = await collectBlobsTolerant(this.eventsContainer.listBlobsFlat({ prefix }));
    // Bounded-parallel (002 §4.2): a long-lived family's events/ prefix has one day-blob per
    // day of family lifetime, and every one of them must be inspected (the subject's lines
    // may be in any of them) — sequential one-at-a-time round-trips risk the request timeout.
    await mapWithConcurrency(blobs, ERASURE_CONCURRENCY, async (blob) => {
      await eraseSubjectFromEventDayBlob(this.eventsContainer, blob.name, userId);
    });
  }
}

// Bounded like the §2.9 usage-increment retry loop (002 §2.9) — only the CURRENT UTC day
// blob can race a concurrent §3.2 append at all (past days are append-dead), so in practice
// this resolves on the first or second attempt.
const EVENTS_REWRITE_MAX_ATTEMPTS = 3;

/**
 * One day blob's filtered rewrite (008 §4.3, 002 §4.2): read all lines + capture the ETag in
 * a single GET; if none of them carry the subject's userId, leave the blob untouched; else
 * delete it `If-Match`-guarded (a 412 — a concurrent append changed the ETag, or a 404 — the
 * blob vanished from under us — both mean "state changed, re-read and retry"), recreate
 * create-if-not-exists (swallowing 409 — a concurrent §3.2 writer, or a concurrent erasure of
 * a DIFFERENT subject, may have recreated it first), then re-append the filtered lines. No
 * other member's line is ever lost: the recreate-race unions whatever a concurrent writer
 * appended in between with our own re-appended filtered history, and readers already sort by
 * recordedAt (002 §3.2/§3.3).
 */
async function eraseSubjectFromEventDayBlob(
  container: ContainerClient,
  blobPath: string,
  userId: string,
): Promise<void> {
  const client = container.getAppendBlobClient(blobPath);

  for (let attempt = 0; attempt < EVENTS_REWRITE_MAX_ATTEMPTS; attempt += 1) {
    let lines: string[];
    let etag: string | undefined;
    try {
      const response = await client.download();
      const buffer = response.readableStreamBody ? await streamToBuffer(response.readableStreamBody) : Buffer.alloc(0);
      lines = buffer
        .toString("utf-8")
        .split("\n")
        .filter((line) => line.length > 0);
      etag = response.etag;
    } catch (err) {
      if (isNotFound(err)) return; // no blob at all for this day — nothing to erase.
      throw err;
    }

    const hasSubjectLine = lines.some((line) => (JSON.parse(line) as EventLine).userId === userId);
    if (!hasSubjectLine) return; // none of the subject's lines here — leave untouched.

    const filteredLines = lines.filter((line) => (JSON.parse(line) as EventLine).userId !== userId);

    try {
      await client.delete({ conditions: { ifMatch: etag } });
    } catch (err) {
      if ((isPreconditionFailed(err) || isNotFound(err)) && attempt < EVENTS_REWRITE_MAX_ATTEMPTS - 1) {
        continue; // concurrent write changed (or removed) the blob — re-read and retry.
      }
      throw err;
    }

    try {
      await client.create({ conditions: { ifNoneMatch: "*" } });
    } catch (err) {
      if (!isAlreadyExists(err)) throw err; // a concurrent writer recreated it first.
    }

    for (const line of filteredLines) {
      const lineBuffer = Buffer.from(`${line}\n`, "utf-8");
      await client.appendBlock(lineBuffer, lineBuffer.length);
    }
    return;
  }
}
