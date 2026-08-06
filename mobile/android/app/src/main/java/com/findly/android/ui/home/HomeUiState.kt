package com.findly.android.ui.home

/** State surfaced by [HomeStateHolder] (specs/003-android-client.md §12). */
sealed class HomeUiState {
    data object Loading : HomeUiState()
    data object SignedOut : HomeUiState()

    /** A24 (001 §1.5.3, §4.1): the signed-in caller has no `Users` profile row yet —
     * `POST /devices` is not one of the four bootstrap endpoints, so it was never attempted
     * (never a registration [RegistrationStatus.Failed]; not an error at all, just onboarding the
     * user hasn't done yet). Home points them at the same `GroupsListScreen` `ProfileNeeded`
     * first-run flow A21 built (specs/003 §12.2). */
    data class ProfileNeeded(val uid: String) : HomeUiState()

    data class SignedIn(val uid: String, val registration: RegistrationStatus) : HomeUiState()

    enum class RegistrationStatus { Registering, Registered, Failed }
}
