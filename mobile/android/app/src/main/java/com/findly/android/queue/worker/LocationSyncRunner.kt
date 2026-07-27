package com.findly.android.queue.worker

import com.findly.android.location.AccuracyTier
import com.findly.android.location.FixCaptureCoordinator
import com.findly.android.location.settings.DeviceSettingsCoordinator
import com.findly.android.queue.FixSource
import com.findly.android.queue.LocationSyncCoordinator
import com.findly.android.queue.SyncOutcome
import java.time.LocalDate

/** [LocationSyncRunner.runOnce]'s result — thin enough for both `LocationSyncWorker` (maps
 * straight to `Result.success()`/`Result.retry()`) and the foreground-service loop (applies
 * [BackoffPolicy] before its next iteration on [Retry]) to consume directly. */
sealed class RunResult {
    data object Success : RunResult()
    data object Retry : RunResult()
}

/**
 * One periodic-sync cycle (specs/009-device-runtime.md §3.1: "the worker captures a fix and
 * queues it even offline; the upload leg tolerates failure and retries") — deliberately **pure
 * Kotlin, zero `android.*` imports**, so this is where the actual "what does a sync run do" logic
 * lives and is unit-tested; `LocationSyncWorker` (WorkManager) and the §3.2 foreground service are
 * both thin callers of the exact same [runOnce].
 *
 * Order per run: (1) the once-per-local-day gate (§3.3) before ever attempting a periodic
 * capture; (2) capture-and-queue one `source: "periodic"` fix (silently skipped by
 * [FixCaptureCoordinator] itself if paused/no permission/debounced, §1.2); (3) drain the queue via
 * [syncCoordinator], reacting to each [SyncOutcome] via [SyncOutcomeReactor] until the queue is
 * empty, a settings change needs applying, or a non-retryable condition is hit.
 */
class LocationSyncRunner(
    private val currentSyncIntervalMinutes: suspend () -> Int,
    private val lastCaptureDateStore: LastCaptureDateStore,
    private val today: () -> LocalDate,
    private val captureCoordinator: FixCaptureCoordinator,
    private val syncCoordinator: LocationSyncCoordinator,
    private val settingsCoordinator: DeviceSettingsCoordinator,
    private val onReRegisterDevice: suspend () -> Unit,
    private val onSignedOut: suspend () -> Unit,
) {
    suspend fun runOnce(): RunResult {
        maybeCapturePeriodicFix()
        return drainQueue()
    }

    private suspend fun maybeCapturePeriodicFix() {
        val interval = currentSyncIntervalMinutes()
        val today = today()
        if (OnceDailyGate.shouldSkipCapture(interval, today, lastCaptureDateStore.lastCaptureDate())) return

        val captured = captureCoordinator.captureAndQueue(FixSource.Periodic, AccuracyTier.Periodic)
        if (captured != null) lastCaptureDateStore.recordCaptureDate(today)
    }

    private suspend fun drainQueue(): RunResult {
        repeat(MAX_BATCHES_PER_RUN) {
            val outcome = syncCoordinator.syncOnce()
            if (outcome is SyncOutcome.NothingToSync) return RunResult.Success

            when (val reaction = SyncOutcomeReactor.reactionFor(outcome)) {
                SyncReaction.Continue -> Unit // more of the queue may remain - loop again
                is SyncReaction.ApplySettings -> {
                    settingsCoordinator.applySettings(reaction.settings)
                    return RunResult.Success
                }
                SyncReaction.ReRegisterDevice -> {
                    onReRegisterDevice()
                    return RunResult.Success
                }
                SyncReaction.SignedOut -> {
                    onSignedOut()
                    return RunResult.Success
                }
                SyncReaction.RetryTransient -> return RunResult.Retry
            }
        }
        // Defensively bounded (§3.1: "MUST... complete in well under 10 minutes") - a
        // pathologically large backlog is picked up again next run rather than looping forever.
        return RunResult.Success
    }

    private companion object {
        const val MAX_BATCHES_PER_RUN = 20 // 20 * 100 = 2 000 fixes/run, well above the 1 000 cap
    }
}
