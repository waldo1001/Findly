package com.findly.android.ui.groups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.ports.GroupsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [GroupsListStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class GroupsListViewModel(groupsApi: GroupsApi, familyApi: FamilyApi) : ViewModel() {
    private val stateHolder = GroupsListStateHolder(groupsApi, familyApi, viewModelScope)
    val state: StateFlow<GroupsListUiState> = stateHolder.state

    fun refresh() {
        viewModelScope.launch { stateHolder.refresh() }
    }
}

class GroupsListViewModelFactory(
    private val groupsApi: GroupsApi,
    private val familyApi: FamilyApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = GroupsListViewModel(groupsApi, familyApi) as T
}
