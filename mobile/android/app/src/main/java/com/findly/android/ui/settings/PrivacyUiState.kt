package com.findly.android.ui.settings

import com.findly.android.network.ExportResult
import com.findly.android.ui.onboarding.OnboardingVariant

/** A family member the caller (if parent) may export on their behalf (specs/008-privacy-
 * endpoints.md §3 — "a parent may export any current member of their family"). */
data class ExportableMemberUi(val userId: String, val displayName: String)

/** Export sub-flow (008 §3) — independent of the two delete flows below, the same "multiple
 * independent sub-flows in one plain state" shape as `InvitesUiState`
 * (specs/003-android-client.md §12.1). */
sealed class ExportFlow {
    data object Idle : ExportFlow()
    data object Exporting : ExportFlow()

    /** [result]'s raw body is handed to the OS share/save sheet un-parsed (specs/003 §12.4) — the
     * screen consumes this once and calls [PrivacyStateHolder.dismissExportResult]. */
    data class Ready(val result: ExportResult) : ExportFlow()

    data class Failed(val message: String) : ExportFlow()
}

/**
 * Two-step delete-account confirmation (specs/008-privacy-endpoints.md §4.4/§1.3;
 * specs/003-android-client.md §12.4). No network call happens before
 * [DeleteAccountFlow.Step2Confirming] is reached — [PrivacyStateHolder.confirmDeleteAccount] is
 * the only call site that invokes `DELETE /users/me`.
 */
sealed class DeleteAccountFlow {
    data object Idle : DeleteAccountFlow()

    /** First confirm shown. [cascadeWarning] is true when the caller is the last parent / sole
     * member (008 §4.2) — the confirmation copy MUST then carry the cascade wording ("you are the
     * only parent — this deletes the family for everyone"). */
    data class Step1Confirming(val cascadeWarning: Boolean) : DeleteAccountFlow()

    /** Second (final) confirm — the very next step is the network call. */
    data class Step2Confirming(val cascadeWarning: Boolean) : DeleteAccountFlow()

    data class Deleting(val cascadeWarning: Boolean) : DeleteAccountFlow()

    /** The backend `204` succeeded but the Firebase SDK delete failed (typically
     * `requires-recent-login`). NOT a bare-retry state — a retry is a trap, since the session
     * never becomes recent on its own (008 §1.3). The only way out is
     * [PrivacyStateHolder.signOutAfterFirebaseFailure]: sign out, sign back in, and re-run the
     * confirm flow from a fresh session. */
    data object FirebaseRetryNeeded : DeleteAccountFlow()

    data class Failed(val message: String) : DeleteAccountFlow()

    // No terminal "Done" state: success wipes local state and signs out, which flips
    // AuthProvider.authState to SignedOut — FindlyNavHost observes that directly (mirroring the
    // existing SignedIn -> pop-SignIn effect) and returns to Home/sign-in; this screen has
    // nothing left to render by that point.
}

/** Two-step delete-family confirmation (specs/008-privacy-endpoints.md §5.4 — "recommended:
 * require typing the family name"); parent-only. */
sealed class DeleteFamilyFlow {
    data object Idle : DeleteFamilyFlow()

    data class Confirming(val familyName: String, val typedName: String = "") : DeleteFamilyFlow()

    data class Deleting(val familyName: String) : DeleteFamilyFlow()

    data class Failed(val message: String) : DeleteFamilyFlow()
}

/**
 * State for the Settings screen's privacy section (specs/003-android-client.md §12.4; wire shapes
 * 001-api-contract.md §13). Deliberately decoupled from [SettingsStateHolder]'s family/device
 * load — export-self and delete-account MUST be reachable "without contacting support"
 * (specs/008-privacy-endpoints.md §4.4) even for a family-less or profile-less caller, so this
 * state holder loads family context independently and degrades gracefully (parent-only entries
 * simply don't appear) rather than blocking the whole privacy section behind a family load.
 *
 * @property isSoleParent true when the caller's departure would leave the family without any
 *   parent (008 §4.2: they are the last parent, or the sole member) — drives the delete-account
 *   confirmation's cascade wording.
 */
data class PrivacyUiState(
    val isLoadingFamily: Boolean = true,
    val isParent: Boolean = false,
    val isSoleParent: Boolean = false,
    val familyName: String? = null,
    val exportableMembers: List<ExportableMemberUi> = emptyList(),
    val exportFlow: ExportFlow = ExportFlow.Idle,
    val deleteAccountFlow: DeleteAccountFlow = DeleteAccountFlow.Idle,
    val deleteFamilyFlow: DeleteFamilyFlow = DeleteFamilyFlow.Idle,
    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND` on
     * [PrivacyStateHolder.exportSelf]/[PrivacyStateHolder.exportMember] (`GET /export` needs only
     * a profile, 001 §13.1 — never family-scoped) routes to Onboarding instead of the dead-end
     * retryable [ExportFlow.Failed] card. Kept as its own field rather than folded into
     * [exportFlow], mirroring this state's existing "multiple independent sub-flow" shape. */
    val exportRouteToOnboarding: OnboardingVariant? = null,
)
