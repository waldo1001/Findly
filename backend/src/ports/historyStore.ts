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
}
