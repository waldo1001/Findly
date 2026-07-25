package com.findly.android.auth

/** Sign-in state as seen by the rest of the app (specs/003-android-client.md §7). */
sealed interface AuthState {
    data object Loading : AuthState
    data object SignedOut : AuthState
    data class SignedIn(val uid: String) : AuthState
}
