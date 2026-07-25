package com.findly.android.ui.groups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.PlanLimits
import com.findly.android.network.ports.GroupsApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [CreateGroupStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`MapViewModel`). [limits] and
 * [needsDisplayName] are threaded in from [GroupsListUiState.Content], set when the user
 * navigates here (specs/003 §12.2) — see `FindlyNavHost`'s remembered pending-create-context,
 * the same pattern it already uses for `Locate`'s target member. */
class CreateGroupViewModel(
    groupsApi: GroupsApi,
    limits: PlanLimits?,
    val needsDisplayName: Boolean,
) : ViewModel() {
    private val stateHolder = CreateGroupStateHolder(groupsApi, limits, needsDisplayName)
    val state: StateFlow<CreateGroupUiState> = stateHolder.state

    fun validate(name: String, endsAtMillis: Long?, expiryPolicy: String, displayName: String?): String? =
        stateHolder.validate(name, endsAtMillis, expiryPolicy, displayName)

    fun createGroup(name: String, endsAtMillis: Long?, expiryPolicy: String, displayName: String?) {
        viewModelScope.launch { stateHolder.createGroup(name, endsAtMillis, expiryPolicy, displayName) }
    }
}

class CreateGroupViewModelFactory(
    private val groupsApi: GroupsApi,
    private val limits: PlanLimits?,
    private val needsDisplayName: Boolean,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
        CreateGroupViewModel(groupsApi, limits, needsDisplayName) as T
}
