package com.findly.android.ui.devices

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** [SyncIntervalOptions] is pure Kotlin (specs/003-android-client.md §14). Table-driven per
 * specs/010-app-shell-and-screen-ux.md §10: "Dropdown: presents exactly the 001 §1.4 set;
 * selection commits one `PATCH` with the chosen value; below-floor values disabled from
 * `features.limits.minSyncIntervalMinutes`." The commit-on-select behavior itself lives in
 * `DevicesStateHolder` (this object only builds the presented option list). */
class SyncIntervalOptionsTest {

    @Test
    fun `build presents exactly the seven 001 section 1_4 values, in order`() {
        val options = SyncIntervalOptions.build(minSyncIntervalMinutes = 5)
        assertEquals(listOf(5, 10, 15, 30, 60, 120, 1440), options.map { it.value })
    }

    @Test
    fun `labels match the 010 section 4_2 wording`() {
        val options = SyncIntervalOptions.build(minSyncIntervalMinutes = 5)
        assertEquals(
            listOf("5 min", "10 min", "15 min", "30 min", "1 hour", "2 hours", "1 day"),
            options.map { it.label },
        )
    }

    @Test
    fun `a floor of 5 minutes -- the lowest allowed value -- disables nothing`() {
        val options = SyncIntervalOptions.build(minSyncIntervalMinutes = 5)
        assertTrue(options.all { it.enabled })
        assertTrue(options.all { it.disabledReason == null })
    }

    @Test
    fun `values below the plan floor are disabled, at-or-above stay enabled`() {
        val options = SyncIntervalOptions.build(minSyncIntervalMinutes = 15)

        assertFalse(options.first { it.value == 5 }.enabled)
        assertFalse(options.first { it.value == 10 }.enabled)
        assertTrue(options.first { it.value == 15 }.enabled)
        assertTrue(options.first { it.value == 30 }.enabled)
        assertTrue(options.first { it.value == 60 }.enabled)
        assertTrue(options.first { it.value == 120 }.enabled)
        assertTrue(options.first { it.value == 1440 }.enabled)
    }

    @Test
    fun `a disabled option names the plan floor as the reason, never a hardcoded number`() {
        val options = SyncIntervalOptions.build(minSyncIntervalMinutes = 30)

        val disabled5 = options.first { it.value == 5 }
        assertFalse(disabled5.enabled)
        assertTrue(disabled5.disabledReason.orEmpty().contains("30 min"))

        val enabled30 = options.first { it.value == 30 }
        assertTrue(enabled30.enabled)
        assertEquals(null, enabled30.disabledReason)
    }

    @Test
    fun `an extreme floor of 1440 disables every value except 1440`() {
        val options = SyncIntervalOptions.build(minSyncIntervalMinutes = 1440)
        assertTrue(options.filter { it.value != 1440 }.all { !it.enabled })
        assertTrue(options.first { it.value == 1440 }.enabled)
    }
}
