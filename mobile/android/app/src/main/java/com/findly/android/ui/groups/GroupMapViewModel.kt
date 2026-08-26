package com.findly.android.ui.groups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.GroupsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [GroupMapStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). */
class GroupMapViewModel(groupId: String, groupsApi: GroupsApi) : ViewModel() {
    private val stateHolder = GroupMapStateHolder(groupId, groupsApi, viewModelScope)
    val state: StateFlow<GroupMapUiState> = stateHolder.state

    fun refresh() {
        viewModelScope.launch { stateHolder.refresh() }
    }

    /** specs/010 §3.5 — select/deselect a member (toggling); position-only, so a located member's
     * own point is the zoom target directly. */
    fun selectMember(userId: String) = stateHolder.selectMember(userId)

    /** specs/010 §3.5 — tapping the map background deselects. */
    fun deselect() = stateHolder.deselect()

    /** specs/010 §3.4's explicit fit-all action. */
    fun fitAll() = stateHolder.fitAll()
}

class GroupMapViewModelFactory(
    private val groupId: String,
    private val groupsApi: GroupsApi,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = GroupMapViewModel(groupId, groupsApi) as T
}
