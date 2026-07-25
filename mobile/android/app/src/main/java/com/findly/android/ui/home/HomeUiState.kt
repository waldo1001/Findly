package com.findly.android.ui.home

/** State surfaced by [HomeStateHolder] (specs/003-android-client.md §12). */
sealed class HomeUiState {
    data object Loading : HomeUiState()
    data object SignedOut : HomeUiState()
    data class SignedIn(val uid: String, val registration: RegistrationStatus) : HomeUiState()

    enum class RegistrationStatus { Registering, Registered, Failed }
}
