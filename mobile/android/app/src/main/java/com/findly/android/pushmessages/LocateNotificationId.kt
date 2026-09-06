package com.findly.android.pushmessages

/**
 * specs/009-device-runtime.md §5.1 (amended 2026-09-06, A39's final round, finding 1 — Major): the
 * `findly_locate` notification id must be scoped **per request**, not global. [LocateNotifier]'s
 * three callers — [com.findly.android.queue.worker.LocateForegroundService],
 * [com.findly.android.queue.worker.LocateRequestWorker]'s expedited-work foreground info, and the
 * presence-reuse direct-capture branch wired in `AppContainer` — are independently lifecycled.
 * Two `LOCATE_REQUEST`s in flight at once (two family members locating the same device inside the
 * ~45-60s window, or an overlapping locate and presence-reuse capture) can land in different
 * branches; with one global id, whichever finishes first calls
 * `stopForeground(STOP_FOREGROUND_REMOVE)` or [LocateNotifier.cancel] on that shared slot and
 * removes the *other* request's still-active notification — a silent locate, the exact failure
 * specs/009 §5.1's "all three branches MUST post" amendment exists to eliminate. Deriving the id
 * from `requestId` instead means every in-flight request owns its own slot: [LocateNotifier.post],
 * `startForeground`/`ForegroundInfo`, and [LocateNotifier.cancel] across all three branches key
 * off this same value for a given request, so finishing one request only ever touches its own
 * notification.
 *
 * Pure and unit-tested — the decidable part of the fix (same bucket as [LocateNotificationTitle]);
 * [LocateNotifier] itself stays thin, untested Android-framework glue.
 */
object LocateNotificationId {

    /** [com.findly.android.queue.worker.LocationForegroundService.NOTIFICATION_ID] (the presence
     * service) is 1001; reserving [BASE_ID, BASE_ID + ID_RANGE) — starting one above the locate
     * feature's old fixed 2001 — keeps every derived id clear of it and of any other
     * `NotificationManager` id already in use. */
    private const val BASE_ID = 2001
    private const val ID_RANGE = 999_983 // large range: collision across a handful of concurrent requests is negligible

    /**
     * Deterministic: the same `requestId` (a server-issued opaque id, 001 §5.1) always folds to
     * the same slot — [String.hashCode] is specified by the platform to be stable for equal
     * content, not merely stable within one process, so `post`/`startForeground`/`cancel` calls
     * made from different objects for the same request always agree on the id. Different
     * `requestId` values collide only if their hash codes happen to land in the same slot out of
     * ~1,000,000 — unreachable in practice for the handful of locate requests ever concurrently in
     * flight in a family-sized app. A missing/blank `requestId` (malformed push data, §9) folds
     * deterministically too, via [String.hashCode] of the empty string, rather than throwing.
     */
    fun forRequestId(requestId: String): Int {
        val nonNegativeHash = requestId.hashCode() and Int.MAX_VALUE
        return BASE_ID + (nonNegativeHash % ID_RANGE)
    }
}
