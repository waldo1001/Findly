package com.findly.android.ui.family

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [FamilyMembersStateHolder] (specs/003-
 * android-client.md §14; same convention as the retired `SettingsViewModel`). */
class FamilyMembersViewModel(
    familyApi: FamilyApi,
) : ViewModel() {
    private val stateHolder = FamilyMembersStateHolder(familyApi, viewModelScope)
    val state: StateFlow<FamilyMembersUiState> = stateHolder.state

    fun reload() {
        viewModelScope.launch { stateHolder.load() }
    }

    fun updateMemberRole(userId: String, role: String) {
        viewModelScope.launch { stateHolder.updateMember(userId, role = role) }
    }

    fun removeMember(userId: String) {
        viewModelScope.launch { stateHolder.removeMember(userId) }
    }
}

class FamilyMembersViewModelFactory(
    private val familyApi: FamilyApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = FamilyMembersViewModel(familyApi) as T
}
