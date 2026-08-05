package com.findly.android.ui.family

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Thin Android `ViewModel` wrapper — all logic lives in [CreateFamilyStateHolder] (specs/003-
 * android-client.md §14; same convention as `HomeViewModel`/`CreateGroupViewModel`). */
class CreateFamilyViewModel(familyApi: FamilyApi) : ViewModel() {
    private val stateHolder = CreateFamilyStateHolder(familyApi)
    val state: StateFlow<CreateFamilyUiState> = stateHolder.state

    fun createFamily(familyName: String, displayName: String) {
        viewModelScope.launch { stateHolder.createFamily(familyName, displayName) }
    }
}

class CreateFamilyViewModelFactory(private val familyApi: FamilyApi) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = CreateFamilyViewModel(familyApi) as T
}
