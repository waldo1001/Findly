package com.findly.android.applock

/** Result of one owner-authentication attempt (specs/010 section 1.4). */
enum class AuthOutcome { Success, Cancelled, Failed }

/**
 * The platform's owner-authentication, behind an interface so `BiometricPrompt` never appears in
 * unit tests (specs/010 section 10 "App lock"). The real one is [BiometricAppLockAuthenticator].
 */
interface AppLockAuthenticator {
    /** Whether the device can authenticate its owner right now (a screen lock / biometric is set). */
    fun canAuthenticate(): Boolean

    /** Shows the platform prompt and suspends until it resolves. Never throws for cancel/failure. */
    suspend fun authenticate(): AuthOutcome
}
