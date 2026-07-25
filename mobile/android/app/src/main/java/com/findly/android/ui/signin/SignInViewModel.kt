package com.findly.android.ui.signin

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.auth.AuthProvider
import kotlinx.coroutines.flow.StateFlow

/** Thin Android `ViewModel` wrapper — all logic lives in [SignInStateHolder] (specs/003-android-
 * client.md §7, §14; same convention as `InvitesViewModel`). [SignInStateHolder]'s resend-cooldown
 * ticker runs on `viewModelScope`, cancelled automatically when this `ViewModel` is cleared. */
class SignInViewModel(authProvider: AuthProvider) : ViewModel() {
    private val stateHolder = SignInStateHolder(authProvider, viewModelScope)
    val state: StateFlow<SignInUiState> = stateHolder.state

    fun submitPhone(rawInput: String) = stateHolder.submitPhone(rawInput)
    fun submitCode(code: String) = stateHolder.submitCode(code)
    fun resend() = stateHolder.resend()
    fun changeNumber() = stateHolder.changeNumber()
}

/** No DI framework (specs/003 §3) — a plain [ViewModelProvider.Factory]. */
class SignInViewModelFactory(private val authProvider: AuthProvider) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = SignInViewModel(authProvider) as T
}
