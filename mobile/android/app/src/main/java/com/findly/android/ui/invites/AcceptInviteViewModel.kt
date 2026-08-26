package com.findly.android.ui.invites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [AcceptInviteStateHolder] (specs/003-
 * android-client.md §14; same convention as every other `<Feature>ViewModel`). */
class AcceptInviteViewModel(familyApi: FamilyApi) : ViewModel() {
    private val stateHolder = AcceptInviteStateHolder(familyApi)
    val state: StateFlow<AcceptInviteUiState> = stateHolder.state

    fun acceptInvite(inviteCode: String, displayName: String) {
        viewModelScope.launch { stateHolder.acceptInvite(inviteCode, displayName) }
    }
}

class AcceptInviteViewModelFactory(private val familyApi: FamilyApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = AcceptInviteViewModel(familyApi) as T
}
