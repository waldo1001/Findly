package com.findly.android.applock

/** Result of one owner-authentication attempt (specs/010 section 1.4). */
enum class AuthOutcome { Success, Cancelled, Failed }

/** What the device can currently do for owner authentication (specs/010 section 1.4). */
enum class DeviceAuthStatus {
    /** Can authenticate now (`BIOMETRIC_SUCCESS`): the only status that lets the toggle be enabled. */
    Available,

    /** Positive signal that no screen lock / biometric is set (`BIOMETRIC_ERROR_NONE_ENROLLED`):
     * the only status under which an enabled lock lapses. */
    NoScreenLock,

    /** Anything else (hardware unavailable, lockout, unknown, ...): transient or not understood, so
     * an enabled lock STILL locks - the Unlock button prompts and the OS decides. */
    Unavailable,
}

/**
 * The platform's owner-authentication, behind an interface so `BiometricPrompt` never appears in
 * unit tests (specs/010 section 10 "App lock"). The real one is [BiometricAppLockAuthenticator].
 */
interface AppLockAuthenticator {
    fun status(): DeviceAuthStatus

    /** Shows the platform prompt and suspends until it resolves. Never throws for cancel/failure. */
    suspend fun authenticate(): AuthOutcome
}
