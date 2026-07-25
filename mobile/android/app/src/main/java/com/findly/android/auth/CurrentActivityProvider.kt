package com.findly.android.auth

import android.app.Activity

/**
 * Supplies the current foreground [Activity] to [FirebaseAuthProvider], which Firebase phone-auth
 * needs for Play Integrity / reCAPTCHA app verification (specs/003-android-client.md §7) — a
 * thin, framework-touching type (same bucket as
 * [com.findly.android.device.AndroidDeviceInfoProvider]). `MainActivity` registers/clears
 * itself via `AppContainer`; only [FirebaseAuthProvider] consumes this. A `null` result (not
 * realistically reachable — the UI triggered the call) is treated as
 * [PhoneAuthError.APP_VERIFICATION_FAILED] by [FirebaseAuthProvider].
 */
fun interface CurrentActivityProvider {
    fun current(): Activity?
}
