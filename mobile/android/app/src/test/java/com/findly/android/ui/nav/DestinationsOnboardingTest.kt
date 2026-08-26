package com.findly.android.ui.nav

import com.findly.android.ui.onboarding.OnboardingVariant
import org.junit.Assert.assertEquals
import org.junit.Test

/** [Destinations.Onboarding]'s route encoding is plain Kotlin — round-tripped here without any
 * `androidx.navigation` dependency (specs/010-app-shell-and-screen-ux.md §2.2). */
class DestinationsOnboardingTest {

    @Test
    fun `createRoute and parseVariant round-trip both variants`() {
        OnboardingVariant.entries.forEach { variant ->
            val route = Destinations.Onboarding.createRoute(variant)
            val arg = route.removePrefix("onboarding/")
            assertEquals(variant, Destinations.Onboarding.parseVariant(arg))
        }
    }

    @Test
    fun `an unrecognized or missing variant defaults to ProfileLess, never crashes`() {
        assertEquals(OnboardingVariant.ProfileLess, Destinations.Onboarding.parseVariant(null))
        assertEquals(OnboardingVariant.ProfileLess, Destinations.Onboarding.parseVariant(""))
        assertEquals(OnboardingVariant.ProfileLess, Destinations.Onboarding.parseVariant("garbage"))
    }
}
