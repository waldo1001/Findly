package com.findly.android.launch

import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * State surfaced by [LaunchGateStateHolder] (specs/010-app-shell-and-screen-ux.md §1.1 — the
 * launch-resolution table). Replaces the deleted `ui/home/HomeUiState`: the Family Map is now the
 * NavHost start destination, so the probe → register → route decision this used to render as a
 * screen of its own now gates that same root destination instead.
 */
sealed class LaunchUiState {
    data object Loading : LaunchUiState()
    data object SignedOut : LaunchUiState()

    /** A confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` on the `GET /families/me` probe (010
     * §1.1's table, rows 3–4) — the caller carries their own `uid` so [LaunchGateStateHolder.retryRegistration]
     * can re-probe once one of the 010 §2.2 bootstrap paths completes. */
    data class Onboarding(val uid: String, val variant: OnboardingVariant) : LaunchUiState()

    /** Signed in, with either a confirmed profile+family or an inconclusive probe that fails open
     * (010 §1.1 — "a blip MUST NOT strand a valid user in onboarding") — the Family Map root
     * renders. [familyHeader] is `null` only for that inconclusive-probe case, where there is no
     * real family data yet to show; the drawer degrades to a placeholder header rather than
     * blocking the map on it. */
    data class Ready(
        val uid: String,
        val registration: RegistrationStatus,
        val familyHeader: FamilyHeader?,
    ) : LaunchUiState()

    enum class RegistrationStatus { Registering, Registered, Failed }

    /** The 010 §1.2 drawer header ("family name + the caller's display name... cached from the
     * launch probe") — computed once here so the drawer never needs its own network call. */
    data class FamilyHeader(val familyName: String, val callerDisplayName: String, val isParent: Boolean)
}
