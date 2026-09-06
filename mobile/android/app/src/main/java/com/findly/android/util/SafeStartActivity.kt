package com.findly.android.util

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/**
 * Code-review fix (A41 round 2, finding 5): none of `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
 * `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, or a vendor `ACTION_VIEW` link
 * (specs/009-device-runtime.md §3.2) is guaranteed to resolve on every device — a stripped OEM
 * build, Android Go, or (for the vendor link) a device with no browser can all leave nothing to
 * handle the `Intent`, and an unguarded `startActivity` throws `ActivityNotFoundException` on the
 * main thread, which crashes the app. §3.2 is explicit that "Declining is not fatal" — a resolver
 * failure must be exactly as harmless as a user declining. Every battery-optimisation / vendor-link
 * call site MUST go through this rather than a bare `startActivity`.
 *
 * [fallback] mirrors the one path virtually every device can resolve
 * (`MainActivity.openAppSettings()`'s own `ACTION_APPLICATION_DETAILS_SETTINGS` pattern) — pass
 * `null` (the vendor link's case) when there is no sensible fallback and a silent no-op is
 * correct instead.
 */
fun Context.startActivitySafely(intent: Intent, fallback: Intent? = defaultAppSettingsIntent(this)) {
    try {
        startActivity(intent)
    } catch (e: ActivityNotFoundException) {
        if (fallback == null) return
        try {
            startActivity(fallback)
        } catch (e2: ActivityNotFoundException) {
            // No-op: truly nothing left to fall back to.
        }
    }
}

private fun defaultAppSettingsIntent(context: Context): Intent = Intent(
    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
    Uri.fromParts("package", context.packageName, null),
)
