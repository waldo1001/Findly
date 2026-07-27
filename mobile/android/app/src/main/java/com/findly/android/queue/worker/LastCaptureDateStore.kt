package com.findly.android.queue.worker

import java.time.LocalDate

/** Persisted "what device-local calendar day did we last successfully capture-and-queue a fix"
 * marker — [OnceDailyGate] reads it; [FixCaptureCoordinator][com.findly.android.location.FixCaptureCoordinator]'s
 * caller updates it after every successful `captureAndQueue`, regardless of `source` (a manual
 * refresh or locate fulfillment also counts as "reported today", per 000-overview.md §O3's plain
 * reading of "at least one fix per day"). Persisted (not in-memory) so a process restart doesn't
 * forget today's capture and needlessly re-capture on a 1440-interval device. */
interface LastCaptureDateStore {
    suspend fun lastCaptureDate(): LocalDate?
    suspend fun recordCaptureDate(date: LocalDate)
}
