// Blob-backed history (specs/002 §3) — later task (B6). Interface only; no fake/adapter yet.

import type { FixSource } from "./repositories";

export interface FixLine {
  fixId: string;
  recordedAt: string;
  receivedAt: string;
  lat: number;
  lon: number;
  accuracyM: number;
  altitudeM?: number;
  speedMps?: number;
  bearingDeg?: number;
  batteryPct: number;
  source: FixSource;
}

export interface EventLine {
  eventId: string;
  userId: string;
  deviceId: string;
  geofenceId: string;
  geofenceName: string | null;
  lat: number | null;
  lon: number | null;
  radiusM: number | null;
  transition: "enter" | "exit";
  recordedAt: string;
  receivedAt: string;
}

export interface HistoryPage<T> {
  items: T[];
  nextCursor: string | null;
}

export interface HistoryStore {
  /** Appends one JSONL line to history/{familyId}/{userId}/{deviceId}/{yyyy}/{MM}/{dd}.jsonl (002 §3.1). */
  appendFix(familyId: string, userId: string, deviceId: string, fix: FixLine): Promise<void>;
  /** Appends one JSONL line to events/{familyId}/{yyyy}/{MM}/{dd}.jsonl (002 §3.1). */
  appendEvent(familyId: string, event: EventLine): Promise<void>;
  /** Day-blob walk + cursor resume (001 §5.3, 002 §3.3). */
  readFixHistory(
    familyId: string,
    userId: string,
    deviceId: string | undefined,
    from: string,
    to: string,
    limit: number,
    cursor: string | null,
  ): Promise<HistoryPage<FixLine & { deviceId: string }>>;
  /** Day-blob walk + cursor resume (001 §7.4, 002 §3.3). */
  readEventHistory(
    familyId: string,
    from: string,
    to: string,
    userId: string | undefined,
    limit: number,
    cursor: string | null,
  ): Promise<HistoryPage<EventLine>>;
  /** Wipes the whole `history/{familyId}/` and `events/{familyId}/` blob prefixes — family
   * deletion (001 §13.3, 002 §4.2 step 4, B19). Idempotent. */
  deleteFamilyPrefix(familyId: string): Promise<void>;
  /** Wipes the `history/{familyId}/{userId}/` blob prefix only — account deletion's
   * non-cascade path (001 §13.2, 002 §4.2 step 6, B18): the subject's own history, every
   * other member's untouched. Idempotent. */
  deleteUserPrefix(familyId: string, userId: string): Promise<void>;
  /**
   * The interleaved-events filtered rewrite (001 §13.2, 008 §4.3, 002 §4.2): for each
   * `events/{familyId}/{yyyy}/{MM}/{dd}.jsonl` day blob, drops every line carrying the
   * subject's `userId` and leaves every other line untouched (byte-identical) — a
   * `If-Match`-guarded delete + create-if-not-exists + re-append, so a genuinely concurrent
   * §3.2 append to the current UTC day blob can never lose a line (008 §4.3's normative
   * sequence). Skip calling this entirely when the whole family prefix is about to be wiped
   * anyway (the cascade path, 002 §4.2 step 7) — deleteFamilyPrefix already subsumes it.
   * Idempotent: a day blob with none of the subject's lines is left untouched; a blob with
   * no lines at all after filtering is still recreated empty (never left half-deleted).
   */
  eraseUserFromEvents(familyId: string, userId: string): Promise<void>;
}
