package com.findly.android.location

import android.annotation.SuppressLint
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import java.time.Instant
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The real, `FusedLocationProviderClient`-backed [LocationCapturer] (specs/009-device-runtime.md
 * §1.1). Thin, untested Android-framework glue by design — no toolchain here to exercise a real
 * device/emulator GPS fix (same bucket as `AndroidDeviceInfoProvider`, specs/003-android-client.md
 * §3); all suppression/pipeline logic lives in the tested [FixCaptureCoordinator]. Never holds a
 * continuous stream: `getCurrentLocation` is FusedLocationProviderClient's one-shot "give me a
 * single current fix" API (as opposed to `requestLocationUpdates`, which this class never calls).
 * Reads [batteryLevelProvider] at capture time to fill [CapturedFix.batteryPct] — A9's
 * [CapturedFix] shape bakes battery in, so it's this class's job, not its callers'.
 */
class FusedLocationCapturer(
    private val fusedLocationProviderClient: FusedLocationProviderClient,
    private val batteryLevelProvider: BatteryLevelProvider,
) : LocationCapturer {

    @SuppressLint("MissingPermission") // the caller (FixCaptureCoordinator) already gates on permission (§1.2)
    override suspend fun captureFix(accuracy: LocationAccuracyTier, timeoutMillis: Long): CapturedFix? {
        val priority = when (accuracy) {
            LocationAccuracyTier.BALANCED -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            LocationAccuracyTier.HIGH -> Priority.PRIORITY_HIGH_ACCURACY
        }
        val cancellationTokenSource = CancellationTokenSource()
        return try {
            withTimeoutOrNull(timeoutMillis) {
                fusedLocationProviderClient
                    .getCurrentLocation(priority, cancellationTokenSource.token)
                    .await()
                    ?.toCapturedFix(batteryLevelProvider.currentBatteryPct())
            }.also {
                if (it == null) cancellationTokenSource.cancel()
            }
        } catch (e: Exception) {
            // §1.1: "no fix is better than a burned battery" - any failure is a silent null,
            // never an exception surfaced to the caller.
            null
        }
    }
}

private fun android.location.Location.toCapturedFix(batteryPct: Int): CapturedFix = CapturedFix(
    lat = latitude,
    lon = longitude,
    accuracyM = accuracy.toDouble(),
    altitudeM = if (hasAltitude()) altitude else null,
    speedMps = if (hasSpeed()) speed.toDouble() else null,
    bearingDeg = if (hasBearing()) bearing.toDouble() else null,
    recordedAt = Instant.ofEpochMilli(time).toString(),
    batteryPct = batteryPct,
)
