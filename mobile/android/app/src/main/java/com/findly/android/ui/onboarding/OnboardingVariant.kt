package com.findly.android.ui.onboarding

/**
 * The two Onboarding variants (specs/010-app-shell-and-screen-ux.md §2.2) — one route, two shapes,
 * replacing both places this UI lived before this spec (iOS Home's `profileless`/`familyless`
 * branches; Android's `GroupsListScreen` `ProfileNeeded` state — both retired).
 */
enum class OnboardingVariant {
    /** No `Users` profile row exists yet (001-api-contract.md §1.5.3, confirmed `PROFILE_NOT_FOUND`).
     * Welcome copy + a display-name field, then all four 001 §1.5.3 bootstrap paths. */
    ProfileLess,

    /** A profile exists but `familyId` is `null` (001 §1.5.4, confirmed `FAMILY_NOT_FOUND` on a
     * family-scoped load) — a groups-only user. No display-name field (they already have one). */
    FamilyLess,
}
