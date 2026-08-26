package com.findly.android.ui.invites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.DevicesApi
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [AcceptInviteStateHolder] (specs/003-
 * android-client.md §14; same convention as every other `<Feature>ViewModel`). [devicesApi]
 * (review-round addition) backs [loadDisplayNameFallback] only — 001 §4.2's `GET /devices`
 * fallback for the caller's own profile `displayName` when the screen has no explicit prefill. */
class AcceptInviteViewModel(familyApi: FamilyApi, devicesApi: DevicesApi) : ViewModel() {
    private val stateHolder = AcceptInviteStateHolder(familyApi, devicesApi)
    val state: StateFlow<AcceptInviteUiState> = stateHolder.state

    fun acceptInvite(inviteCode: String, displayName: String) {
        viewModelScope.launch { stateHolder.acceptInvite(inviteCode, displayName) }
    }

    fun loadDisplayNameFallback() {
        viewModelScope.launch { stateHolder.loadDisplayNameFallback() }
    }
}

class AcceptInviteViewModelFactory(
    private val familyApi: FamilyApi,
    private val devicesApi: DevicesApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = AcceptInviteViewModel(familyApi, devicesApi) as T
}
