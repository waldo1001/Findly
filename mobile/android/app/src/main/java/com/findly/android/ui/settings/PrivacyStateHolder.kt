package com.findly.android.ui.settings

import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthState
import com.findly.android.network.ApiResult
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.ports.PrivacyApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The Settings screen's privacy section state machine — export, delete-account, delete-family
 * (001-api-contract.md §13; specs/008-privacy-endpoints.md; specs/003-android-client.md §12.4).
 *
 * Deliberately independent of [SettingsStateHolder]: it does its own [FamilyApi.getMyFamily] call
 * and, unlike [SettingsStateHolder], never surfaces a blocking error state when that call fails —
 * export-self and delete-account MUST be reachable without contacting support (008 §4.4) even for
 * a family-less or profile-less caller. Parent-only entries (export-a-member, delete-family)
 * simply stay absent (`isParent = false`) whenever the family context couldn't be loaded.
 */
class PrivacyStateHolder(
    private val privacyApi: PrivacyApi,
    private val familyApi: FamilyApi,
    private val authProvider: AuthProvider,
    private val localStateWiper: LocalStateWiper,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(PrivacyUiState())
    val state: StateFlow<PrivacyUiState> = _state.asStateFlow()

    init {
        scope.launch { loadFamilyContext() }
    }

    suspend fun loadFamilyContext() {
        _state.value = _state.value.copy(isLoadingFamily = true)
        when (val result = familyApi.getMyFamily()) {
            is ApiResult.Success -> {
                val data = result.data
                val isParent = data.me.role == "parent"
                val parentCount = data.members.count { it.role == "parent" }
                _state.value = _state.value.copy(
                    isLoadingFamily = false,
                    isParent = isParent,
                    isSoleParent = isParent && parentCount <= 1,
                    familyName = data.familyName,
                    exportableMembers = data.members
                        .filterNot { it.userId == data.me.userId }
                        .map { ExportableMemberUi(it.userId, it.displayName) },
                )
            }
            is ApiResult.Failure -> {
                // Family-less / profile-less caller (008 §4.4) — Export-self and Delete-account
                // stay reachable below; only the parent-only entries have nothing to show.
                _state.value = _state.value.copy(
                    isLoadingFamily = false,
                    isParent = false,
                    isSoleParent = false,
                    familyName = null,
                    exportableMembers = emptyList(),
                )
            }
        }
    }

    // ------------------------------------------------------------------
    // Export (008 §3)
    // ------------------------------------------------------------------

    suspend fun exportSelf() = export(userId = null)

    suspend fun exportMember(userId: String) = export(userId)

    private suspend fun export(userId: String?) {
        _state.value = _state.value.copy(exportFlow = ExportFlow.Exporting, exportRouteToOnboarding = null)
        when (val result = privacyApi.exportData(userId)) {
            is ApiResult.Success -> _state.value = _state.value.copy(exportFlow = ExportFlow.Ready(result.data))
            is ApiResult.Failure -> {
                // specs/010-app-shell-and-screen-ux.md §2.1: GET /export needs only a profile
                // (001 §13.1) — never family-scoped.
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = false)
                _state.value = if (variant != null) {
                    _state.value.copy(exportFlow = ExportFlow.Idle, exportRouteToOnboarding = variant)
                } else {
                    _state.value.copy(exportFlow = ExportFlow.Failed(result.error.userMessage()))
                }
            }
        }
    }

    fun dismissExportResult() {
        _state.value = _state.value.copy(exportFlow = ExportFlow.Idle)
    }

    // ------------------------------------------------------------------
    // Delete account (008 §4) — two-step gating; no network call before Step2Confirming
    // ------------------------------------------------------------------

    fun startDeleteAccount() {
        _state.value = _state.value.copy(
            deleteAccountFlow = DeleteAccountFlow.Step1Confirming(cascadeWarning = _state.value.isSoleParent),
        )
    }

    fun advanceDeleteAccountConfirmation() {
        val current = _state.value.deleteAccountFlow as? DeleteAccountFlow.Step1Confirming ?: return
        _state.value = _state.value.copy(deleteAccountFlow = DeleteAccountFlow.Step2Confirming(current.cascadeWarning))
    }

    fun cancelDeleteAccount() {
        _state.value = _state.value.copy(deleteAccountFlow = DeleteAccountFlow.Idle)
    }

    /** The only call site that invokes `DELETE /users/me` — only proceeds from
     * [DeleteAccountFlow.Step2Confirming]. */
    suspend fun confirmDeleteAccount() {
        val current = _state.value.deleteAccountFlow as? DeleteAccountFlow.Step2Confirming ?: return
        _state.value = _state.value.copy(deleteAccountFlow = DeleteAccountFlow.Deleting(current.cascadeWarning))
        when (val result = privacyApi.deleteAccount()) {
            is ApiResult.Success -> finishAccountDeletion()
            is ApiResult.Failure -> _state.value = _state.value.copy(
                deleteAccountFlow = DeleteAccountFlow.Failed(result.error.userMessage()),
            )
        }
    }

    /**
     * The 008 §1.3 recovery for a Firebase-delete failure — deliberately NOT a retry of
     * [AuthProvider.deleteCurrentUser]. `user.delete()` commonly fails with `requires-recent-
     * login`, and by this point `DELETE /users/me` has already succeeded irreversibly: the
     * session is never going to become "recent" on its own, so a bare retry would fail forever
     * (the reason [DeleteAccountFlow.FirebaseRetryNeeded] no longer means "retry" — it means
     * "needs this escape hatch"). Signs the user out; `DELETE /users/me` is an idempotent no-op
     * for a profile-less caller (008 §4.1) and this privacy UI stays reachable without a profile
     * (008 §4.4), so after signing back in and re-running [startDeleteAccount]/
     * [confirmDeleteAccount] the session is recent and [finishAccountDeletion] succeeds. Deliberately
     * does NOT wipe local state here — the account isn't actually gone from this device's
     * perspective until that later, successful run completes.
     */
    suspend fun signOutAfterFirebaseFailure() {
        if (_state.value.deleteAccountFlow !is DeleteAccountFlow.FirebaseRetryNeeded) return
        authProvider.signOut()
        _state.value = _state.value.copy(deleteAccountFlow = DeleteAccountFlow.Idle)
    }

    /** Called only after a `204` from `DELETE /users/me` (008 §1.3's ordering). Captures the uid
     * before [AuthProvider.signOut] flips [AuthProvider.authState] to `SignedOut`. */
    private suspend fun finishAccountDeletion() {
        val uid = (authProvider.authState.value as? AuthState.SignedIn)?.uid
        val firebaseOk = authProvider.deleteCurrentUser()
        if (!firebaseOk) {
            _state.value = _state.value.copy(deleteAccountFlow = DeleteAccountFlow.FirebaseRetryNeeded)
            return
        }
        if (uid != null) {
            localStateWiper.wipeAll(uid)
        }
        authProvider.signOut()
        _state.value = _state.value.copy(deleteAccountFlow = DeleteAccountFlow.Idle)
    }

    // ------------------------------------------------------------------
    // Delete family (008 §5) — parent-only; typed-name gating (§5.4)
    // ------------------------------------------------------------------

    fun startDeleteFamily() {
        val current = _state.value
        if (!current.isParent) return
        _state.value = current.copy(
            deleteFamilyFlow = DeleteFamilyFlow.Confirming(familyName = current.familyName.orEmpty()),
        )
    }

    fun updateDeleteFamilyTypedName(text: String) {
        val current = _state.value.deleteFamilyFlow as? DeleteFamilyFlow.Confirming ?: return
        _state.value = _state.value.copy(deleteFamilyFlow = current.copy(typedName = text))
    }

    fun cancelDeleteFamily() {
        _state.value = _state.value.copy(deleteFamilyFlow = DeleteFamilyFlow.Idle)
    }

    /** Only proceeds — and only then calls `DELETE /families/me` — when the typed name matches
     * the family name exactly (specs/008 §5.4). */
    suspend fun confirmDeleteFamily() {
        val current = _state.value.deleteFamilyFlow as? DeleteFamilyFlow.Confirming ?: return
        if (current.typedName.trim() != current.familyName) return
        _state.value = _state.value.copy(deleteFamilyFlow = DeleteFamilyFlow.Deleting(current.familyName))
        when (val result = privacyApi.deleteFamily()) {
            is ApiResult.Success -> _state.value = _state.value.copy(
                deleteFamilyFlow = DeleteFamilyFlow.Idle,
                isParent = false,
                isSoleParent = false,
                familyName = null,
                exportableMembers = emptyList(),
            )
            is ApiResult.Failure -> _state.value = _state.value.copy(
                deleteFamilyFlow = DeleteFamilyFlow.Failed(result.error.userMessage()),
            )
        }
    }
}
