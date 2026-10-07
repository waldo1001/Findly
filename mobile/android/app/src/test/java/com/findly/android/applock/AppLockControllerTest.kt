package com.findly.android.applock

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/010 section 1.4 / section 10 "App lock": the state machine behind the lock screen and the
 * Privacy & data toggle, driven through a fake [AppLockAuthenticator] (BiometricPrompt never runs
 * in unit tests). */
class AppLockControllerTest {

    private class FakeAuthenticator(
        var available: Boolean = true,
        var outcome: AuthOutcome = AuthOutcome.Success,
    ) : AppLockAuthenticator {
        var calls = 0
        override fun canAuthenticate() = available
        override suspend fun authenticate(): AuthOutcome {
            calls++
            return outcome
        }
    }

    private val minute = 60_000L
    private val t0 = 10_000_000L

    private fun controller(
        enabled: Boolean = false,
        auth: FakeAuthenticator = FakeAuthenticator(),
        store: AppLockStore = AppLockStore(InMemoryAppLockPersistence()).also { it.setEnabled(enabled) },
    ) = AppLockController(store, auth)

    // ---- cold start -------------------------------------------------------------------------

    @Test
    fun `enabled cold start covers the UI from the first frame, before auth restore resolves`() {
        assertTrue(controller(enabled = true).locked.value)
    }

    @Test
    fun `disabled cold start never covers`() {
        assertFalse(controller(enabled = false).locked.value)
    }

    @Test
    fun `cold start resolving to signed in stays locked`() {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.SignedIn)
        assertTrue(c.locked.value)
    }

    @Test
    fun `cold start resolving to signed out lifts the cover - lock is only for signed-in users`() {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.SignedOut)
        assertFalse(c.locked.value)
    }

    @Test
    fun `signing in later in the same process does not lock`() {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.SignedOut)
        c.onAuthState(AppLockAuth.SignedIn)
        assertFalse(c.locked.value)
    }

    @Test
    fun `auth still loading keeps the cover`() {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.Loading)
        assertTrue(c.locked.value)
    }

    @Test
    fun `signing out while locked lifts the lock`() {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.SignedIn)
        c.onAuthState(AppLockAuth.SignedOut)
        assertFalse(c.locked.value)
    }

    @Test
    fun `enabled but device credential gone - fails open instead of trapping the user`() {
        val c = controller(enabled = true, auth = FakeAuthenticator(available = false))
        c.onAuthState(AppLockAuth.SignedIn)
        assertFalse(c.locked.value)
    }

    // ---- background / foreground -------------------------------------------------------------

    private fun signedInController(): AppLockController {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.SignedIn)
        return c
    }

    @Test
    fun `return after 4 minutes does not re-lock`() = runTest {
        val c = signedInController()
        c.unlock()
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = true, now = t0 + 4 * minute)
        assertFalse(c.locked.value)
    }

    @Test
    fun `return after 5 minutes re-locks`() = runTest {
        val c = signedInController()
        c.unlock()
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = true, now = t0 + 5 * minute)
        assertTrue(c.locked.value)
    }

    @Test
    fun `timestamp is consumed - a foreground event without a new background does not re-lock`() = runTest {
        val c = signedInController()
        c.unlock()
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = true, now = t0 + 6 * minute)
        c.unlock()
        c.onForegrounded(signedIn = true, now = t0 + 7 * minute)
        assertFalse(c.locked.value)
    }

    @Test
    fun `disabled never re-locks after a long background`() {
        val c = controller(enabled = false)
        c.onAuthState(AppLockAuth.SignedIn)
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = true, now = t0 + 60 * minute)
        assertFalse(c.locked.value)
    }

    @Test
    fun `signed out never re-locks after a long background`() {
        val c = controller(enabled = true)
        c.onAuthState(AppLockAuth.SignedOut)
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = false, now = t0 + 60 * minute)
        assertFalse(c.locked.value)
    }

    @Test
    fun `backgrounding records the timestamp in the store`() {
        val store = AppLockStore(InMemoryAppLockPersistence())
        val c = controller(store = store)
        c.onBackgrounded(t0)
        assertEquals(t0, store.backgroundedAt())
    }

    @Test
    fun `a still-locked app stays locked across foreground events`() {
        val c = signedInController() // cold-start lock, never unlocked
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = true, now = t0 + 1)
        assertTrue(c.locked.value)
    }

    // ---- unlock -----------------------------------------------------------------------------

    @Test
    fun `successful authentication unlocks`() = runTest {
        val c = signedInController()
        assertEquals(AuthOutcome.Success, c.unlock())
        assertFalse(c.locked.value)
    }

    @Test
    fun `cancel keeps the lock`() = runTest {
        val c = controller(enabled = true, auth = FakeAuthenticator(outcome = AuthOutcome.Cancelled))
        c.onAuthState(AppLockAuth.SignedIn)
        assertEquals(AuthOutcome.Cancelled, c.unlock())
        assertTrue(c.locked.value)
    }

    @Test
    fun `failure keeps the lock with no retry counter - a later attempt is always allowed`() = runTest {
        val auth = FakeAuthenticator(outcome = AuthOutcome.Failed)
        val c = controller(enabled = true, auth = auth)
        c.onAuthState(AppLockAuth.SignedIn)
        repeat(5) { c.unlock() }
        assertEquals(5, auth.calls)
        auth.outcome = AuthOutcome.Success
        c.unlock()
        assertFalse(c.locked.value)
    }

    @Test
    fun `auto prompt is offered once per lock and re-armed when the lock engages again`() = runTest {
        val c = signedInController()
        assertTrue(c.consumeAutoPrompt())
        assertFalse(c.consumeAutoPrompt())
        c.unlock()
        c.onBackgrounded(t0)
        c.onForegrounded(signedIn = true, now = t0 + 5 * minute)
        assertTrue(c.consumeAutoPrompt())
    }

    // ---- enabling ---------------------------------------------------------------------------

    @Test
    fun `enabling requires one successful authentication`() = runTest {
        val auth = FakeAuthenticator()
        val c = controller(enabled = false, auth = auth)
        assertEquals(EnableResult.Enabled, c.setEnabled(true))
        assertTrue(c.enabled.value)
        assertEquals(1, auth.calls)
    }

    @Test
    fun `enabling with a cancelled authentication leaves it off`() = runTest {
        val c = controller(enabled = false, auth = FakeAuthenticator(outcome = AuthOutcome.Cancelled))
        assertEquals(EnableResult.NotAuthenticated, c.setEnabled(true))
        assertFalse(c.enabled.value)
    }

    @Test
    fun `enabling is unavailable without a device credential and never prompts`() = runTest {
        val auth = FakeAuthenticator(available = false)
        val c = controller(enabled = false, auth = auth)
        assertFalse(c.isAvailable())
        assertEquals(EnableResult.Unavailable, c.setEnabled(true))
        assertFalse(c.enabled.value)
        assertEquals(0, auth.calls)
    }

    @Test
    fun `enabling does not lock the current session`() = runTest {
        val c = controller(enabled = false)
        c.onAuthState(AppLockAuth.SignedIn)
        c.setEnabled(true)
        assertFalse(c.locked.value)
    }

    @Test
    fun `disabling needs no authentication and lifts any lock`() = runTest {
        val auth = FakeAuthenticator()
        val c = controller(enabled = true, auth = auth)
        c.onAuthState(AppLockAuth.SignedIn)
        assertEquals(EnableResult.Disabled, c.setEnabled(false))
        assertFalse(c.enabled.value)
        assertFalse(c.locked.value)
        assertEquals(0, auth.calls)
    }

    // ---- wipe -------------------------------------------------------------------------------

    @Test
    fun `the end-of-session wipe turns the lock off`() {
        val store = AppLockStore(InMemoryAppLockPersistence()).also { it.setEnabled(true) }
        val c = controller(store = store)
        c.onAuthState(AppLockAuth.SignedIn)
        store.clear()
        c.onAuthState(AppLockAuth.SignedOut)
        assertFalse(c.enabled.value)
        assertFalse(c.locked.value)
    }
}
