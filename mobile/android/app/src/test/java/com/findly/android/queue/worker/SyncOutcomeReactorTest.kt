package com.findly.android.queue.worker

import com.findly.android.network.ApiError
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.queue.SyncOutcome
import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §9's error-handling/backoff rules, isolated from any WorkManager/
 * foreground-service glue. */
class SyncOutcomeReactorTest {

    @Test
    fun `nothing to sync and a clean sync both just continue`() {
        assertEquals(SyncReaction.Continue, SyncOutcomeReactor.reactionFor(SyncOutcome.NothingToSync))
        assertEquals(SyncReaction.Continue, SyncOutcomeReactor.reactionFor(SyncOutcome.Synced(1, 0)))
    }

    @Test
    fun `a rejected batch continues - the queue already handled dropping offenders`() {
        assertEquals(SyncReaction.Continue, SyncOutcomeReactor.reactionFor(SyncOutcome.Rejected(setOf("f1"))))
    }

    @Test
    fun `transient failure retries`() {
        assertEquals(SyncReaction.RetryTransient, SyncOutcomeReactor.reactionFor(SyncOutcome.TransientFailure))
    }

    @Test
    fun `paused applies the echoed settings immediately`() {
        val reaction = SyncOutcomeReactor.reactionFor(SyncOutcome.Paused(30, false))

        assertEquals(SyncReaction.ApplySettings(DeviceSettingsSnapshot(30, false)), reaction)
    }

    @Test
    fun `DEVICE_NOT_FOUND re-registers`() {
        val error = ApiError.DeviceNotFound(message = "not found", requestId = null)

        assertEquals(SyncReaction.ReRegisterDevice, SyncOutcomeReactor.reactionFor(SyncOutcome.OtherFailure(error)))
    }

    @Test
    fun `a second AUTH_TOKEN_EXPIRED signs out`() {
        val error = ApiError.AuthTokenExpired(message = "expired", requestId = null)

        assertEquals(SyncReaction.SignedOut, SyncOutcomeReactor.reactionFor(SyncOutcome.OtherFailure(error)))
    }

    @Test
    fun `any other error falls back to retry`() {
        val error = ApiError.InternalError(message = "boom", requestId = null)

        assertEquals(SyncReaction.RetryTransient, SyncOutcomeReactor.reactionFor(SyncOutcome.OtherFailure(error)))
    }
}
