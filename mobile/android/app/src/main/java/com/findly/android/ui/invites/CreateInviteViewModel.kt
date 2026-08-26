package com.findly.android.ui.invites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [CreateInviteStateHolder] (specs/003-
 * android-client.md §14; same convention as every other `<Feature>ViewModel`). */
class CreateInviteViewModel(familyApi: FamilyApi) : ViewModel() {
    private val stateHolder = CreateInviteStateHolder(familyApi)
    val state: StateFlow<CreateInviteUiState> = stateHolder.state

    fun createInvite(role: String, emailHint: String? = null) {
        viewModelScope.launch { stateHolder.createInvite(role, emailHint) }
    }

    /** specs/010-app-shell-and-screen-ux.md §5.1 bullet 6 — "Create another" resets the form
     * without leaving the screen. */
    fun reset() {
        stateHolder.reset()
    }
}

class CreateInviteViewModelFactory(private val familyApi: FamilyApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = CreateInviteViewModel(familyApi) as T
}
