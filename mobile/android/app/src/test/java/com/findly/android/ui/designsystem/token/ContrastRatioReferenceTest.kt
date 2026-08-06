package com.findly.android.ui.designsystem.token

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Sanity-checks [contrastRatio] itself against a published WCAG 2.1 reference pairing, before any
 * other test in this package is allowed to be trusted (A28, specs/003-android-client.md §4.1–§4.2:
 * "the rest of the suite is worthless" if this formula can't reproduce a known-correct number).
 *
 * `#767676` on `#FFFFFF` is a widely-cited WCAG reference value = **4.54:1** (per the WCAG 2.1
 * relative-luminance formula: linearize each sRGB channel, `L = 0.2126R + 0.7152G + 0.0722B`, then
 * `(L1 + 0.05) / (L2 + 0.05)` with L1 the lighter of the two).
 */
class ContrastRatioReferenceTest {

    @Test
    fun `767676 on FFFFFF must compute to 4point54 to 1 — if this fails, the formula is wrong and nothing else in this suite can be trusted`() {
        val ratio = contrastRatio(Color(0xFF767676), Color(0xFFFFFFFF))

        assertEquals(
            "contrastRatio(#767676, #FFFFFF) must be 4.54:1 (published WCAG 2.1 reference value). " +
                "Got $ratio instead — the relative-luminance/contrast formula in ContrastRatio.kt is " +
                "wrong, and every other assertion in this test suite is worthless until this passes.",
            4.54,
            ratio,
            0.005,
        )
    }
}
