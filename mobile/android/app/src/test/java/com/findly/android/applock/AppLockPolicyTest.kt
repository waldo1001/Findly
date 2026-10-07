package com.findly.android.applock

import androidx.biometric.BiometricManager
import org.junit.Assert.assertEquals
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
    fun `lock lapses only on the positive no-screen-lock signal`() {
        assertTrue(AppLockPolicy.isEffective(enabled = true, status = DeviceAuthStatus.Available))
        assertFalse(AppLockPolicy.isEffective(enabled = true, status = DeviceAuthStatus.NoScreenLock))
        // A transient or unknown failure must still lock (spec 010 1.4): an unopenable lock is
        // recoverable, an opened gate is not.
        assertTrue(AppLockPolicy.isEffective(enabled = true, status = DeviceAuthStatus.Unavailable))
        assertFalse(AppLockPolicy.isEffective(enabled = false, status = DeviceAuthStatus.Available))
    }

    @Test
    fun `toggle is interactive when strictly available, or when on so it can be switched off`() {
        assertTrue(AppLockPolicy.toggleInteractive(enabled = false, status = DeviceAuthStatus.Available))
        assertFalse(AppLockPolicy.toggleInteractive(enabled = false, status = DeviceAuthStatus.NoScreenLock))
        assertFalse(AppLockPolicy.toggleInteractive(enabled = false, status = DeviceAuthStatus.Unavailable))
        assertTrue(AppLockPolicy.toggleInteractive(enabled = true, status = DeviceAuthStatus.NoScreenLock))
        assertTrue(AppLockPolicy.toggleInteractive(enabled = true, status = DeviceAuthStatus.Unavailable))
    }

    @Test
    fun `BiometricManager result codes map to a status - only NONE_ENROLLED is NoScreenLock`() {
        assertEquals(DeviceAuthStatus.Available, AppLockPolicy.statusFor(BiometricManager.BIOMETRIC_SUCCESS))
        assertEquals(DeviceAuthStatus.NoScreenLock, AppLockPolicy.statusFor(BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED))
        listOf(
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE,
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE,
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED,
            BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED,
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN,
            12345,
        ).forEach { assertEquals("code $it", DeviceAuthStatus.Unavailable, AppLockPolicy.statusFor(it)) }
    }
}
