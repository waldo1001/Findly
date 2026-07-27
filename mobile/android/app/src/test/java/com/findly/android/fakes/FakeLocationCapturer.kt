package com.findly.android.fakes

import com.findly.android.location.CapturedFix
import com.findly.android.location.LocationAccuracyTier
import com.findly.android.location.LocationCapturer

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Scripts
 * [captureFix]'s return value via [fixToReturn]; records every requested [LocationAccuracyTier]/
 * [timeoutMillis] pair so a test can assert the right tier and timeout were asked for
 * (specs/009-device-runtime.md §1.1). */
class FakeLocationCapturer(var fixToReturn: CapturedFix?) : LocationCapturer {
    val requestedTiers = mutableListOf<LocationAccuracyTier>()
    val requestedTimeouts = mutableListOf<Long>()

    override suspend fun captureFix(accuracy: LocationAccuracyTier, timeoutMillis: Long): CapturedFix? {
        requestedTiers.add(accuracy)
        requestedTimeouts.add(timeoutMillis)
        return fixToReturn
    }
}
