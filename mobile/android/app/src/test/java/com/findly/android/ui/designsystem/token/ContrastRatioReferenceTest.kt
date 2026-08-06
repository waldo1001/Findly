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

    // Two edge-case reference values (A28 addendum, iOS I29 review parity): the mid-range
    // #767676/#FFFFFF pair above can pass even with a coefficient or luminance-ordering bug that
    // happens to cancel out in that particular range — these two bracket the whole possible output
    // and catch that class of error directly.

    @Test
    fun `black on white must compute to exactly 21 to 1 — the maximum value the formula can produce`() {
        val ratio = contrastRatio(Color(0xFF000000), Color(0xFFFFFFFF))

        assertEquals(
            "contrastRatio(#000000, #FFFFFF) must be exactly 21:1 — L(black)=0, L(white)=1, so " +
                "(1+0.05)/(0+0.05) = 21 exactly. Got $ratio instead.",
            21.0,
            ratio,
            0.0001,
        )
    }

    @Test
    fun `identical colors must compute to exactly 1 to 1 — the minimum value the formula can produce`() {
        val ratio = contrastRatio(Color(0xFF4A4A4A), Color(0xFF4A4A4A))

        assertEquals(
            "contrastRatio(x, x) for any color must be exactly 1:1 — identical luminances make " +
                "(L+0.05)/(L+0.05) = 1 regardless of which color. Got $ratio instead.",
            1.0,
            ratio,
            0.0001,
        )
    }
}
