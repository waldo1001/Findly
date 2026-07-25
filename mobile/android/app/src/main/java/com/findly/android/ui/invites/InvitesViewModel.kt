package com.findly.android.ui.invites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [InvitesStateHolder] (specs/003-android-
 * client.md §14; same convention as `HomeViewModel`/`HistoryViewModel`). */
class InvitesViewModel(familyApi: FamilyApi) : ViewModel() {
    private val stateHolder = InvitesStateHolder(familyApi)
    val state: StateFlow<InvitesUiState> = stateHolder.state

    fun createInvite(role: String, emailHint: String? = null) {
        viewModelScope.launch { stateHolder.createInvite(role, emailHint) }
    }

    fun acceptInvite(inviteCode: String, displayName: String) {
        viewModelScope.launch { stateHolder.acceptInvite(inviteCode, displayName) }
    }
}

class InvitesViewModelFactory(private val familyApi: FamilyApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = InvitesViewModel(familyApi) as T
}
