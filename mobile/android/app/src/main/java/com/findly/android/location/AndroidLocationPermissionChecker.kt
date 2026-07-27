package com.findly.android.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

/**
 * Real, `Context`-backed [LocationPermissionState] (specs/009-device-runtime.md §7: "revocation
 * while running stops capture without crashing" — re-checking on every call, never cached, is
 * what makes that true). Fine location is the minimum bar for any capture; background-location
 * gating for the foreground-service/WorkManager paths is a scheduling-layer concern
 * (specs/003-android-client.md §11), not this class's. Thin Android-framework glue, untested.
 */
class AndroidLocationPermissionChecker(private val context: Context) : LocationPermissionState {
    override suspend fun isGranted(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
}
