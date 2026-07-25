package com.findly.android.ui.groups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.GroupsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [GroupJoinStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class GroupJoinViewModel(groupsApi: GroupsApi, val needsDisplayName: Boolean) : ViewModel() {
    private val stateHolder = GroupJoinStateHolder(groupsApi, needsDisplayName)
    val state: StateFlow<GroupJoinUiState> = stateHolder.state

    fun join(code: String, displayName: String?) {
        viewModelScope.launch { stateHolder.join(code, displayName) }
    }
}

class GroupJoinViewModelFactory(
    private val groupsApi: GroupsApi,
    private val needsDisplayName: Boolean,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = GroupJoinViewModel(groupsApi, needsDisplayName) as T
}
