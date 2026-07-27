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
    fun `nothing to sync just continues`() {
        assertEquals(SyncReaction.Continue, SyncOutcomeReactor.reactionFor(SyncOutcome.NothingToSync))
    }

    @Test
    fun `a successful sync applies its mandatory deviceSettings piggyback (001 §5_1) - every accepted response carries it, not just a 403`() {
        val outcome = SyncOutcome.Synced(
            accepted = 1,
            duplicates = 0,
            deviceSettings = DeviceSettingsSnapshot(30, true),
            geofenceEtag = "\"1\"",
        )

        val reaction = SyncOutcomeReactor.reactionFor(outcome)

        assertEquals(SyncReaction.Synced(DeviceSettingsSnapshot(30, true), "\"1\""), reaction)
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
