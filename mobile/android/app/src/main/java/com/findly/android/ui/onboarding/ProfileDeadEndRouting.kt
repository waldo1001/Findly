package com.findly.android.ui.onboarding

import com.findly.android.network.ApiError

/**
 * The shared pure classifier behind the 010 §2.1 routing rule — the fix for the field-reported bug
 * where a signed-in user without a profile (or, on a family-scoped screen, without a family) got a
 * dead-end "we couldn't find your profile/family" error card with a Retry that could never succeed
 * (retrying a `GET`/`PATCH` cannot create a profile — only the four 001 §1.5.3 bootstrap endpoints
 * can). Every `<Feature>StateHolder`'s *load* path (never a mutation/action failure, which keeps
 * its existing inline rendering per §2.1) runs its failure through [classify]: a non-`null` result
 * means "route to Onboarding instead of rendering a retryable error state"; `null` means "render
 * the existing error/retry UI as before — this isn't one of the two routed 404s."
 *
 * No `android.*`/framework import — plain Kotlin/JVM, unit-tested with plain JUnit
 * (specs/003-android-client.md §14), mirroring every other pure `<Feature>StateHolder` in this
 * module.
 */
object ProfileDeadEndRouting {

    /**
     * @param error the failed call's [ApiError].
     * @param familyScoped whether the endpoint that failed requires an existing family (001 §1.5
     *   point 4 — member/parent-role endpoints). When `false` (a profile-only endpoint, e.g.
     *   `GET /export`, or a screen that is explicitly family-agnostic like Groups, 010 §2.1's
     *   "Group screens are unaffected — they only need a profile"), a `FAMILY_NOT_FOUND` is left
     *   for the caller's existing handling rather than routed.
     * @return [OnboardingVariant.ProfileLess] for a confirmed `PROFILE_NOT_FOUND` (always, on any
     *   screen); [OnboardingVariant.FamilyLess] for a confirmed `FAMILY_NOT_FOUND` **only** when
     *   [familyScoped]; `null` for every other error, which the caller keeps rendering as its
     *   existing inline/retryable error state.
     */
    fun classify(error: ApiError, familyScoped: Boolean): OnboardingVariant? = when {
        error is ApiError.ProfileNotFound -> OnboardingVariant.ProfileLess
        familyScoped && error is ApiError.FamilyNotFound -> OnboardingVariant.FamilyLess
        else -> null
    }
}
