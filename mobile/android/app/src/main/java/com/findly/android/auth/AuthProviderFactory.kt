package com.findly.android.auth

/** Mirrors `BuildConfig.AUTH_MODE`'s two legal values (specs/003-android-client.md §13). */
enum class AuthMode {
    InsecureLocal,
    Firebase,
    ;

    companion object {
        fun fromBuildConfigValue(value: String): AuthMode = when (value) {
            "insecure-local" -> InsecureLocal
            "firebase" -> Firebase
            else -> error("Unknown AUTH_MODE '$value' (expected 'insecure-local' or 'firebase')")
        }
    }
}

/**
 * Picks the [AuthProvider] implementation for the current build (specs/003 §7, §13).
 * [firebaseAuthProvider] is a **lazy** supplier, invoked only when [mode] is [AuthMode.Firebase] —
 * this keeps this factory (and its test) pure-JVM: [com.findly.android.AppContainer] (the
 * only real caller) passes `{ FirebaseAuthProvider(FirebaseAuth.getInstance(), activityProvider) }`,
 * so `FirebaseAuth.getInstance()` is only ever reached on a real device/emulator, never from a
 * unit test or an `insecure-local` build.
 */
object AuthProviderFactory {
    fun create(mode: AuthMode, firebaseProjectId: String, firebaseAuthProvider: () -> AuthProvider): AuthProvider =
        when (mode) {
            AuthMode.InsecureLocal -> DevAuthProvider(firebaseProjectId = firebaseProjectId)
            AuthMode.Firebase -> firebaseAuthProvider()
        }
}
