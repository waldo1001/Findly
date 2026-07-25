package com.findly.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.auth.AuthProvider
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.ports.PrivacyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [PrivacyStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`SettingsViewModel`). */
class PrivacyViewModel(
    privacyApi: PrivacyApi,
    familyApi: FamilyApi,
    authProvider: AuthProvider,
    localStateWiper: LocalStateWiper,
) : ViewModel() {
    private val stateHolder = PrivacyStateHolder(privacyApi, familyApi, authProvider, localStateWiper, viewModelScope)
    val state: StateFlow<PrivacyUiState> = stateHolder.state

    fun exportSelf() {
        viewModelScope.launch { stateHolder.exportSelf() }
    }

    fun exportMember(userId: String) {
        viewModelScope.launch { stateHolder.exportMember(userId) }
    }

    fun dismissExportResult() {
        stateHolder.dismissExportResult()
    }

    fun startDeleteAccount() {
        stateHolder.startDeleteAccount()
    }

    fun advanceDeleteAccountConfirmation() {
        stateHolder.advanceDeleteAccountConfirmation()
    }

    fun cancelDeleteAccount() {
        stateHolder.cancelDeleteAccount()
    }

    fun confirmDeleteAccount() {
        viewModelScope.launch { stateHolder.confirmDeleteAccount() }
    }

    /** 008 §1.3's recovery for a Firebase-delete failure — signs out so the user can sign back in
     * and re-run delete-account with a fresh session; deliberately NOT a bare retry (see
     * [PrivacyStateHolder.signOutAfterFirebaseFailure]'s doc). */
    fun signOutAfterFirebaseFailure() {
        viewModelScope.launch { stateHolder.signOutAfterFirebaseFailure() }
    }

    fun startDeleteFamily() {
        stateHolder.startDeleteFamily()
    }

    fun updateDeleteFamilyTypedName(text: String) {
        stateHolder.updateDeleteFamilyTypedName(text)
    }

    fun cancelDeleteFamily() {
        stateHolder.cancelDeleteFamily()
    }

    fun confirmDeleteFamily() {
        viewModelScope.launch { stateHolder.confirmDeleteFamily() }
    }
}

class PrivacyViewModelFactory(
    private val privacyApi: PrivacyApi,
    private val familyApi: FamilyApi,
    private val authProvider: AuthProvider,
    private val localStateWiper: LocalStateWiper,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        PrivacyViewModel(privacyApi, familyApi, authProvider, localStateWiper) as T
}
