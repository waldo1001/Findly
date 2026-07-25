package com.findly.android.ui.groups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.GroupsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [GroupDetailStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class GroupDetailViewModel(groupId: String, groupsApi: GroupsApi) : ViewModel() {
    private val stateHolder = GroupDetailStateHolder(groupId, groupsApi, viewModelScope)
    val state: StateFlow<GroupDetailUiState> = stateHolder.state

    fun reload() {
        viewModelScope.launch { stateHolder.load() }
    }

    fun rename(name: String) {
        viewModelScope.launch { stateHolder.rename(name) }
    }

    fun updateEndsAt(endsAtIso: String) {
        viewModelScope.launch { stateHolder.updateEndsAt(endsAtIso) }
    }

    fun rotateCode() {
        viewModelScope.launch { stateHolder.rotateCode() }
    }

    fun kickMember(userId: String) {
        viewModelScope.launch { stateHolder.kickMember(userId) }
    }

    fun deleteGroup() {
        viewModelScope.launch { stateHolder.deleteGroup() }
    }

    fun leaveGroup() {
        viewModelScope.launch { stateHolder.leaveGroup() }
    }
}

class GroupDetailViewModelFactory(
    private val groupId: String,
    private val groupsApi: GroupsApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = GroupDetailViewModel(groupId, groupsApi) as T
}
