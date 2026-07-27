package com.findly.android.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * The background-location variant of [AndroidLocationPermissionChecker] — `GeofencingClient`
 * registration needs `ACCESS_BACKGROUND_LOCATION` to reliably fire transitions while the app is
 * not in the foreground (specs/009-device-runtime.md §7; the A11 task brief: "confirm your
 * registration code checks the current permission state (background location, since
 * GeofencingClient needs it) before calling GeofencingClient.addGeofences"). Android only
 * introduced background location as a *separate* permission at API 29 (Q) — before that, fine
 * location alone already implies background access, so this checks fine location unconditionally
 * and background location only on API 29+, mirroring the platform's own staging (specs/003-android-
 * client.md §11). Thin Android-framework glue, untested (same bucket as
 * [AndroidLocationPermissionChecker]).
 */
class AndroidBackgroundLocationPermissionChecker(private val context: Context) : LocationPermissionState {
    override suspend fun isGranted(): Boolean {
        val fineGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fineGranted) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }
}
