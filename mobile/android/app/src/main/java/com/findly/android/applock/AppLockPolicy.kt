package com.findly.android.applock

import androidx.biometric.BiometricManager

/** Pure policy of specs/010 section 1.4 "When it locks" (unit-tested without a UI). */
object AppLockPolicy {
    /** A return to the foreground after at least this long in the background re-locks. */
    const val RELOCK_AFTER_MILLIS: Long = 5L * 60 * 1000

    /**
     * Whether the lock screen must be showing. Never when [enabled] is false or the user is not
     * [signedIn]; always on a cold start; otherwise when the app was backgrounded at least
     * [RELOCK_AFTER_MILLIS] ago. A [backgroundedAt] in the future (the wall clock moved backwards)
     * fails safe and locks - a lock must never be skippable by changing the clock.
     */
    fun shouldLock(
        enabled: Boolean,
        signedIn: Boolean,
        isColdStart: Boolean,
        backgroundedAt: Long?,
        now: Long,
    ): Boolean {
        if (!enabled || !signedIn) return false
        if (isColdStart) return true
        if (backgroundedAt == null) return false
        val away = now - backgroundedAt
        return away < 0 || away >= RELOCK_AFTER_MILLIS
    }

    /** Enabled, and the device has not positively reported "no screen lock" (010 1.4 "Credential
     * removed later"): with no screen lock the phone itself is open and the gate adds nothing. Only
     * [DeviceAuthStatus.NoScreenLock] lapses the lock; a transient [DeviceAuthStatus.Unavailable]
     * must never open the gate. Feed this as `shouldLock`'s `enabled`. */
    fun isEffective(enabled: Boolean, status: DeviceAuthStatus): Boolean =
        enabled && status != DeviceAuthStatus.NoScreenLock

    /** The Privacy & data toggle is interactive when the device is strictly [DeviceAuthStatus.Available],
     * or when it is on (so it can always be switched off). */
    fun toggleInteractive(enabled: Boolean, status: DeviceAuthStatus): Boolean =
        enabled || status == DeviceAuthStatus.Available

    /** Maps `BiometricManager.canAuthenticate(BIOMETRIC_WEAK or DEVICE_CREDENTIAL)` to a status. */
    fun statusFor(biometricResult: Int): DeviceAuthStatus = when (biometricResult) {
        BiometricManager.BIOMETRIC_SUCCESS -> DeviceAuthStatus.Available
        BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> DeviceAuthStatus.NoScreenLock
        else -> DeviceAuthStatus.Unavailable
    }
}
