package com.findly.android.ui.family

import com.findly.android.network.ports.FamilyApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The Family screen's pure state machine (specs/010-app-shell-and-screen-ux.md §4.1's `Family`
 * route; wire shapes specs/001-api-contract.md §3.2/§3.5/§3.6).
 *
 * STUB (deliberately wrong, not absent): every method is a no-op so
 * `FamilyMembersStateHolderTest` fails on its assertions, not on a missing type — TDD red, about
 * to be replaced.
 */
class FamilyMembersStateHolder(
    private val familyApi: FamilyApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<FamilyMembersUiState>(FamilyMembersUiState.Loading)
    val state: StateFlow<FamilyMembersUiState> = _state.asStateFlow()

    suspend fun load() = Unit

    suspend fun updateMember(userId: String, role: String? = null, displayName: String? = null) = Unit

    suspend fun removeMember(userId: String) = Unit
}
