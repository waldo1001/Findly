package com.findly.android.applock

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/010 section 1.4 "When it locks" and section 10 "App lock": the pure `shouldLock` policy. */
class AppLockPolicyTest {

    private val minute = 60_000L
    private val t0 = 1_000_000L

    private fun lock(
        enabled: Boolean = true,
        signedIn: Boolean = true,
        isColdStart: Boolean = false,
        backgroundedAt: Long? = null,
        now: Long = t0,
    ) = AppLockPolicy.shouldLock(enabled, signedIn, isColdStart, backgroundedAt, now)

    @Test
    fun `signed out never locks - cold start`() = assertFalse(lock(signedIn = false, isColdStart = true))

    @Test
    fun `signed out never locks - long background`() =
        assertFalse(lock(signedIn = false, backgroundedAt = t0 - 60 * minute))

    @Test
    fun `disabled never locks - cold start`() = assertFalse(lock(enabled = false, isColdStart = true))

    @Test
    fun `disabled never locks - long background`() =
        assertFalse(lock(enabled = false, backgroundedAt = t0 - 60 * minute))

    @Test
    fun `enabled and signed in always locks on cold start`() = assertTrue(lock(isColdStart = true))

    @Test
    fun `background shorter than 5 minutes does not lock`() =
        assertFalse(lock(backgroundedAt = t0 - (5 * minute - 1)))

    @Test
    fun `background of exactly 5 minutes locks`() = assertTrue(lock(backgroundedAt = t0 - 5 * minute))

    @Test
    fun `background longer than 5 minutes locks`() = assertTrue(lock(backgroundedAt = t0 - 30 * minute))

    @Test
    fun `no recorded background time and not a cold start does not lock`() =
        assertFalse(lock(backgroundedAt = null))

    @Test
    fun `clock moved backwards fails safe and locks`() = assertTrue(lock(backgroundedAt = t0 + minute))

    @Test
    fun `lock is effective only while the device can still authenticate its owner`() {
        assertTrue(AppLockPolicy.isEffective(enabled = true, deviceCanAuthenticate = true))
        assertFalse(AppLockPolicy.isEffective(enabled = true, deviceCanAuthenticate = false))
        assertFalse(AppLockPolicy.isEffective(enabled = false, deviceCanAuthenticate = true))
    }

    @Test
    fun `toggle is interactive when available, or when on so it can be switched off`() {
        assertTrue(AppLockPolicy.toggleInteractive(enabled = false, deviceCanAuthenticate = true))
        assertFalse(AppLockPolicy.toggleInteractive(enabled = false, deviceCanAuthenticate = false))
        assertTrue(AppLockPolicy.toggleInteractive(enabled = true, deviceCanAuthenticate = false))
        assertTrue(AppLockPolicy.toggleInteractive(enabled = true, deviceCanAuthenticate = true))
    }
}
