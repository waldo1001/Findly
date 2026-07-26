package com.findly.android.pushmessages

import com.findly.android.fakes.FakeLocateApi
import com.findly.android.fakes.FakeLocationCapturer
import com.findly.android.location.CapturedFix
import com.findly.android.location.LocationAccuracyTier
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.1; 001-api-contract.md §8.1/§6.3. [LocateRequestPushHandler]
 * deliberately takes no pause/tracking-enabled input at all — a `LOCATE_REQUEST` MUST be fulfilled
 * even while the device is paused (009 §5.1), unlike the periodic capture pipeline's own §1.2
 * suppression rules — so "still fulfills while paused" is proven here simply by there being
 * nothing in this handler's inputs *to* suppress it. */
class LocateRequestPushHandlerTest {

    private val fix = CapturedFix(
        recordedAt = "2026-07-19T09:05:00Z",
        lat = 51.05,
        lon = 3.71,
        accuracyM = 8.0,
        altitudeM = null,
        speedMps = null,
        bearingDeg = null,
        batteryPct = 65,
    )

    private fun handler(
        capturer: FakeLocationCapturer,
        locateApi: FakeLocateApi,
        deviceId: String? = "device-1",
        nowIso: String = "2026-07-19T09:06:00Z",
    ) = LocateRequestPushHandler(
        locationCapturer = capturer,
        locateApi = locateApi,
        deviceIdProvider = { deviceId },
        fixIdGenerator = { "fix-test-id" },
        now = { Instant.parse(nowIso) },
    )

    private fun data(
        requestId: String? = "lr_1",
        expiresAt: String? = "2026-07-19T09:06:12Z",
    ): Map<String, String> = buildMap {
        requestId?.let { put("requestId", it) }
        expiresAt?.let { put("expiresAt", it) }
        put("requestedByName", "Eric")
    }

    @Test
    fun `within window captures a HIGH-accuracy fix and fulfills with source locate`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()

        handler(capturer, locateApi).handle(data())

        assertEquals(listOf(LocationAccuracyTier.HIGH), capturer.requestedTiers)
        val call = locateApi.fulfillLocateRequestCalls.single()
        assertEquals("lr_1", call.requestId)
        assertEquals("device-1", call.deviceId)
        assertEquals("locate", call.fix.source)
        assertEquals("fix-test-id", call.fix.fixId)
        assertEquals(fix.lat, call.fix.lat, 0.0)
        assertEquals(fix.batteryPct, call.fix.batteryPct)
    }

    @Test
    fun `expired past the 10-minute grace is ignored silently`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()
        // expiresAt 09:06:12Z + 10min = 09:16:12Z; one second past it.
        handler(capturer, locateApi, nowIso = "2026-07-19T09:16:13Z").handle(data())

        assertTrue(capturer.requestedTiers.isEmpty())
        assertTrue(locateApi.fulfillLocateRequestCalls.isEmpty())
    }

    @Test
    fun `exactly at the 10-minute grace boundary still fulfills`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()
        handler(capturer, locateApi, nowIso = "2026-07-19T09:16:12Z").handle(data())

        assertEquals(1, locateApi.fulfillLocateRequestCalls.size)
    }

    @Test
    fun `capture failure gives up silently without calling fulfill`() = runTest {
        val capturer = FakeLocationCapturer(fixToReturn = null)
        val locateApi = FakeLocateApi()

        handler(capturer, locateApi).handle(data())

        assertTrue(locateApi.fulfillLocateRequestCalls.isEmpty())
    }

    @Test
    fun `missing requestId drops the payload without crashing`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()

        handler(capturer, locateApi).handle(data(requestId = null))

        assertTrue(capturer.requestedTiers.isEmpty())
        assertTrue(locateApi.fulfillLocateRequestCalls.isEmpty())
    }

    @Test
    fun `malformed expiresAt drops the payload without crashing`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()

        handler(capturer, locateApi).handle(data(expiresAt = "not-a-date"))

        assertTrue(locateApi.fulfillLocateRequestCalls.isEmpty())
    }

    @Test
    fun `missing expiresAt drops the payload without crashing`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()

        handler(capturer, locateApi).handle(data(expiresAt = null))

        assertTrue(locateApi.fulfillLocateRequestCalls.isEmpty())
    }

    @Test
    fun `no registered device (signed out) drops the request`() = runTest {
        val capturer = FakeLocationCapturer(fix)
        val locateApi = FakeLocateApi()

        handler(capturer, locateApi, deviceId = null).handle(data())

        assertTrue(capturer.requestedTiers.isEmpty())
        assertTrue(locateApi.fulfillLocateRequestCalls.isEmpty())
    }
}
