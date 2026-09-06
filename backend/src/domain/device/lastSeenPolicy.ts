// specs/001 §4.2 (amended 2026-09-06) — every device-originated call (`POST /devices`,
// `POST /locations`, `POST /geofence-events`, `POST /locate-requests/{id}/fulfill`) MUST
// refresh a device's `lastSeenAt`, but specs/002 §2.4 caps the actual write to at most once
// per minute per device so the hot paths (§5.1/§7.3/§6.3) don't triple their Table Storage
// traffic just to bump a timestamp. Pure decision only — callers own the actual
// DeviceRepo.putDevice write; this file has zero Azure/Google imports.

export const LAST_SEEN_WRITE_SKIP_MS = 60 * 1000;

/** True once at least LAST_SEEN_WRITE_SKIP_MS has elapsed since the device's currently
 * stored `lastSeenAt` — i.e. the call site should write a fresh value. `>=`, not `>`, so
 * the boundary itself (exactly one minute) still refreshes. */
export function shouldRefreshLastSeen(lastSeenAt: string, now: Date): boolean {
  return now.getTime() - new Date(lastSeenAt).getTime() >= LAST_SEEN_WRITE_SKIP_MS;
}
