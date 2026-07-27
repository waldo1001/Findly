package com.findly.android.location

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertNull
import org.junit.Test

/** [UnimplementedLocationCapturer] is A9's placeholder wiring target until A10 lands the real
 * FusedLocationProviderClient-backed [LocationCapturer] (specs/009-device-runtime.md §1) — this
 * locks its "always give up silently" contract so a future accidental behavior change is caught. */
class UnimplementedLocationCapturerTest {

    @Test
    fun `always returns null regardless of accuracy tier`() = runTest {
        assertNull(UnimplementedLocationCapturer.captureFix(LocationAccuracyTier.HIGH))
        assertNull(UnimplementedLocationCapturer.captureFix(LocationAccuracyTier.BALANCED))
    }
}
