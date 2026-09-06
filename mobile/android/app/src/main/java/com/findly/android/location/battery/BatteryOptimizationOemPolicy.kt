package com.findly.android.location.battery

/**
 * specs/009-device-runtime.md §3.2: "On OEMs known to kill foreground services
 * (`Build.MANUFACTURER` ∈ a small maintained list: Xiaomi, Huawei, Oppo, OnePlus, Vivo, Samsung),
 * the Devices screen MUST additionally link to the vendor-specific steps (dontkillmyapp.com)."
 *
 * Pure — takes the raw `Build.MANUFACTURER` string rather than reading it itself, so this stays
 * unit-testable with no Android framework in the loop. Comparison is case-insensitive:
 * `Build.MANUFACTURER` is documented as lowercase in practice but that is not a contract, and a
 * silent case mismatch here would be a false negative on a real device.
 */
object BatteryOptimizationOemPolicy {
    // Kept as a small, explicitly "maintained" list per the spec wording, rather than a
    // heuristic - dontkillmyapp.com's own page slugs, lowercase.
    private val VENDOR_KILL_LIST = setOf("xiaomi", "huawei", "oppo", "oneplus", "vivo", "samsung")

    fun showsVendorLink(manufacturer: String): Boolean = normalize(manufacturer) in VENDOR_KILL_LIST

    /** `null` when [manufacturer] is not on the list — mirrors [showsVendorLink] exactly, so a
     * caller never has to duplicate the membership check to decide whether to use the URL. */
    fun vendorLinkUrl(manufacturer: String): String? {
        val normalized = normalize(manufacturer)
        return if (normalized in VENDOR_KILL_LIST) "https://dontkillmyapp.com/$normalized" else null
    }

    private fun normalize(manufacturer: String) = manufacturer.trim().lowercase()
}
