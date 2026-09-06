package com.findly.android.location.battery

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/009-device-runtime.md §3.2: "On OEMs known to kill foreground services
 * (`Build.MANUFACTURER` ∈ a small maintained list: Xiaomi, Huawei, Oppo, OnePlus, Vivo, Samsung),
 * the Devices screen MUST additionally link to the vendor-specific steps (dontkillmyapp.com)."
 */
class BatteryOptimizationOemPolicyTest {

    @Test
    fun `every listed OEM shows the vendor link, case-insensitively`() {
        for (manufacturer in listOf(
            "Xiaomi", "XIAOMI", "xiaomi",
            "Huawei", "Oppo", "OnePlus", "oneplus", "Vivo", "Samsung", "SAMSUNG",
        )) {
            assertTrue("manufacturer=$manufacturer", BatteryOptimizationOemPolicy.showsVendorLink(manufacturer))
        }
    }

    @Test
    fun `an OEM not on the list does not show the vendor link`() {
        for (manufacturer in listOf("Google", "Motorola", "Sony", "Nothing", "")) {
            assertFalse("manufacturer=$manufacturer", BatteryOptimizationOemPolicy.showsVendorLink(manufacturer))
        }
    }

    @Test
    fun `vendorLinkUrl returns a dontkillmyapp_com page for a listed OEM`() {
        assertEquals("https://dontkillmyapp.com/xiaomi", BatteryOptimizationOemPolicy.vendorLinkUrl("Xiaomi"))
        assertEquals("https://dontkillmyapp.com/samsung", BatteryOptimizationOemPolicy.vendorLinkUrl("SAMSUNG"))
    }

    @Test
    fun `vendorLinkUrl is null for an OEM not on the list`() {
        assertNull(BatteryOptimizationOemPolicy.vendorLinkUrl("Google"))
    }
}
