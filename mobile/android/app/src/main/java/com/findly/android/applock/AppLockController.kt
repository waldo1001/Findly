package com.findly.android.applock

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Auth restore state as the lock sees it (mapped from `AuthState` by the UI layer). */
enum class AppLockAuth { Loading, SignedOut, SignedIn }

/** Outcome of switching the Privacy & data toggle (specs/010 section 1.4 "Enabling"). */
enum class EnableResult { Enabled, Disabled, Unavailable, NotAuthenticated }

/**
 * Pure state machine behind the lock screen and the Privacy & data toggle (specs/010 section 1.4).
 * One instance per process (owned by `AppContainer`) so the lock survives Activity recreation; it
 * is a cold start exactly when the instance is new. Never signs anyone out or wipes anything.
 */
class AppLockController(
    private val store: AppLockStore,
    private val authenticator: AppLockAuthenticator,
) {
    private var coldStartPending = true
    private var autoPromptPending = false
    private var authenticating = false

    // Enabled cold start: the cover is up from the very first frame, before auth restore resolves.
    private val _locked = MutableStateFlow(AppLockPolicy.isEffective(store.enabled.value, authenticator.status()))

    /** Whether the opaque lock screen must be showing (also the `locked` input of the pending link). */
    val locked: StateFlow<Boolean> = _locked.asStateFlow()

    /** The setting; the Privacy & data toggle and the recents-screenshot flag observe it. */
    val enabled: StateFlow<Boolean> get() = store.enabled

    init {
        autoPromptPending = _locked.value
    }

    /** Whether the toggle can be touched at all (on, so it can be turned off; or available). */
    fun toggleInteractive(): Boolean = AppLockPolicy.toggleInteractive(store.enabled.value, authenticator.status())

    /** Whether the toggle may be switched on: the device can authenticate its owner. */
    fun isAvailable(): Boolean = authenticator.status() == DeviceAuthStatus.Available

    /** Feed every auth-state change. Resolves the cold-start decision once restore finishes. */
    fun onAuthState(auth: AppLockAuth) {
        when (auth) {
            AppLockAuth.Loading -> Unit
            AppLockAuth.SignedOut -> {
                coldStartPending = false
                setLocked(false) // lock exists only while signed in
            }
            AppLockAuth.SignedIn -> if (coldStartPending) {
                coldStartPending = false
                setLocked(shouldLock(signedIn = true, isColdStart = true, backgroundedAt = null, now = 0L))
            }
        }
    }

    /** Activity left the foreground: remember when (judged on return by [AppLockPolicy]). */
    fun onBackgrounded(now: Long) {
        store.recordBackgrounded(now)
    }

    /** Activity returned to the foreground. The recorded timestamp is consumed. */
    fun onForegrounded(signedIn: Boolean, now: Long) {
        val at = store.backgroundedAt()
        store.clearBackgrounded()
        if (coldStartPending) return // auth restore not finished; the cold-start cover is up already
        if (shouldLock(signedIn, isColdStart = false, backgroundedAt = at, now = now)) setLocked(true)
    }

    /** Runs the platform prompt. Success lifts the lock; cancel/failure leave it up (no counter). */
    suspend fun unlock(): AuthOutcome {
        if (authenticating) return AuthOutcome.Cancelled
        authenticating = true
        try {
            val outcome = authenticator.authenticate()
            if (outcome == AuthOutcome.Success) setLocked(false)
            return outcome
        } finally {
            authenticating = false
        }
    }

    /** True exactly once per appearance of the lock screen: the automatic first prompt. */
    fun consumeAutoPrompt(): Boolean {
        if (!autoPromptPending) return false
        autoPromptPending = false
        return true
    }

    /** The toggle. On needs availability and one successful authentication; off needs neither. */
    suspend fun setEnabled(enable: Boolean): EnableResult {
        if (!enable) {
            store.setEnabled(false)
            setLocked(false)
            return EnableResult.Disabled
        }
        if (!isAvailable()) return EnableResult.Unavailable
        if (authenticating) return EnableResult.NotAuthenticated
        authenticating = true
        val outcome = try {
            authenticator.authenticate()
        } finally {
            authenticating = false
        }
        if (outcome != AuthOutcome.Success) return EnableResult.NotAuthenticated
        store.setEnabled(true)
        return EnableResult.Enabled
    }

    // The lock lapses only on a positive "no screen lock" signal (AppLockPolicy.isEffective).
    private fun shouldLock(signedIn: Boolean, isColdStart: Boolean, backgroundedAt: Long?, now: Long) =
        AppLockPolicy.shouldLock(
            enabled = AppLockPolicy.isEffective(store.enabled.value, authenticator.status()),
            signedIn = signedIn,
            isColdStart = isColdStart,
            backgroundedAt = backgroundedAt,
            now = now,
        )

    private fun setLocked(value: Boolean) {
        if (value && !_locked.value) autoPromptPending = true
        _locked.value = value
    }
}
