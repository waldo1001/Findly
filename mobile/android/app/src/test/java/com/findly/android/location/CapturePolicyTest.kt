package com.findly.android.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §1.1 "Accepting a recent cached position" — the pure age
 * arithmetic behind [FusedLocationCapturer]'s `CurrentLocationRequest.setMaxUpdateAgeMillis` value
 * and its `lastLocation` fallback, independent of any Play-services/Android framework class. */
class CapturePolicyTest {

    @Test
    fun `BALANCED requests accept an already-computed position up to 2 minutes old`() {
        assertEquals(120_000L, CapturePolicy.maxUpdateAgeMillisFor(LocationAccuracyTier.BALANCED))
    }

    @Test
    fun `HIGH requests never accept an already-computed position - locate and manual want a fresh fix`() {
        assertEquals(0L, CapturePolicy.maxUpdateAgeMillisFor(LocationAccuracyTier.HIGH))
    }

    @Test
    fun `BALANCED - a cached fallback exactly at the sync interval is accepted`() {
        assertTrue(
            CapturePolicy.acceptsCachedFallback(
                accuracy = LocationAccuracyTier.BALANCED,
                cachedAgeMillis = 900_000L,
                maxCachedAgeMillis = 900_000L,
            ),
        )
    }

    @Test
    fun `BALANCED - a cached fallback older than the sync interval is rejected`() {
        assertFalse(
            CapturePolicy.acceptsCachedFallback(
                accuracy = LocationAccuracyTier.BALANCED,
                cachedAgeMillis = 900_001L,
                maxCachedAgeMillis = 900_000L,
            ),
        )
    }

    @Test
    fun `BALANCED - a negative age (clock skew) is rejected, not accepted`() {
        assertFalse(
            CapturePolicy.acceptsCachedFallback(
                accuracy = LocationAccuracyTier.BALANCED,
                cachedAgeMillis = -1L,
                maxCachedAgeMillis = 900_000L,
            ),
        )
    }

    @Test
    fun `HIGH never accepts the cached fallback, regardless of age - locate and manual MUST NOT use either shortcut`() {
        assertFalse(
            CapturePolicy.acceptsCachedFallback(
                accuracy = LocationAccuracyTier.HIGH,
                cachedAgeMillis = 0L,
                maxCachedAgeMillis = Long.MAX_VALUE,
            ),
        )
    }
}
