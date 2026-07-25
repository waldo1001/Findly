package com.findly.android.ui.settings

import com.findly.android.auth.AuthState
import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.FakeLocalStateWiper
import com.findly.android.fakes.FakePrivacyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.ExportResult
import com.findly.android.network.dto.CallerRoleDto
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.MemberDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [PrivacyStateHolder] is pure Kotlin — tested with fakes (specs/003-android-client.md §12.4,
 * §16's test-checklist additions; wire shapes 001-api-contract.md §13; concepts specs/008-privacy-
 * endpoints.md). Deliberately decoupled from [SettingsStateHolder]'s family/device load: export-
 * self and delete-account MUST be reachable even when the family load fails (008 §4.4 "reachable
 * without contacting support").
 */
class PrivacyStateHolderTest {

    private fun familyOf(vararg members: MemberDto, meIndex: Int = 0): FamilyMeResponseDto = FamilyMeResponseDto(
        familyId = "fam_test",
        familyName = "Wauters",
        createdAt = "2026-07-01T00:00:00Z",
        me = CallerRoleDto(members[meIndex].userId, members[meIndex].role),
        members = members.toList(),
    )

    private val soleParent = MemberDto("uid-parent", "parent", "Eric", "2026-07-01T00:00:00Z")
    private val coParent = MemberDto("uid-parent2", "parent", "Ana", "2026-07-01T00:00:00Z")
    private val plainMember = MemberDto("uid-member", "member", "Noor", "2026-07-02T00:00:00Z")

    private fun holder(
        privacyApi: FakePrivacyApi = FakePrivacyApi(),
        familyApi: FakeFamilyApi = FakeFamilyApi(),
        authProvider: FakeAuthProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-parent")),
        localStateWiper: FakeLocalStateWiper = FakeLocalStateWiper(),
        scope: kotlinx.coroutines.CoroutineScope,
    ) = PrivacyStateHolder(privacyApi, familyApi, authProvider, localStateWiper, scope)

    // ------------------------------------------------------------------
    // Family-context load (decoupled from SettingsStateHolder)
    // ------------------------------------------------------------------

    @Test
    fun `load with a sole-parent family sets isParent and isSoleParent true`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        val state = h.state.value
        assertTrue(state.isParent)
        assertTrue(state.isSoleParent)
        assertEquals("Wauters", state.familyName)
        assertEquals(listOf("uid-member"), state.exportableMembers.map { it.userId })
        assertFalse(state.isLoadingFamily)
    }

    @Test
    fun `load with a co-parent family sets isSoleParent false`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, coParent, meIndex = 0), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        val state = h.state.value
        assertTrue(state.isParent)
        assertFalse(state.isSoleParent)
    }

    @Test
    fun `load as a non-parent member never reports isSoleParent even if somehow the only parent counts to one`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember, meIndex = 1), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        val state = h.state.value
        assertFalse(state.isParent)
        assertFalse(state.isSoleParent)
    }

    @Test
    fun `getMyFamily failure (family-less or profile-less) still yields a usable content state, never a blocking Error`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1"))
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        val state = h.state.value
        assertFalse(state.isLoadingFamily)
        assertFalse(state.isParent)
        assertFalse(state.isSoleParent)
        assertEquals(null, state.familyName)
        assertTrue(state.exportableMembers.isEmpty())
    }

    // ------------------------------------------------------------------
    // Export (008 §3)
    // ------------------------------------------------------------------

    @Test
    fun `exportSelf calls exportData with a null userId and surfaces the raw result unparsed`() = runTest {
        val privacyApi = FakePrivacyApi().apply {
            exportDataResult = ApiResult.Success(
                ExportResult(body = "hello".toByteArray(), suggestedFileName = "findly-export-x.json", contentType = "application/json"),
                features = null,
            )
        }
        val h = holder(privacyApi = privacyApi, scope = backgroundScope)
        runCurrent()

        h.exportSelf()

        assertEquals(listOf(null), privacyApi.exportDataCalls)
        val flow = h.state.value.exportFlow
        assertTrue(flow is ExportFlow.Ready)
        assertEquals("hello", String((flow as ExportFlow.Ready).result.body))
    }

    @Test
    fun `exportMember calls exportData with the given userId`() = runTest {
        val privacyApi = FakePrivacyApi()
        val h = holder(privacyApi = privacyApi, scope = backgroundScope)
        runCurrent()

        h.exportMember("uid-member")

        assertEquals(listOf("uid-member"), privacyApi.exportDataCalls)
    }

    @Test
    fun `export failure surfaces the user-facing message, never raw server text`() = runTest {
        val privacyApi = FakePrivacyApi().apply {
            exportDataResult = ApiResult.Failure(
                ApiError.LimitExceeded(limit = "exportsPerDay", message = "raw debug text", requestId = "r_2"),
            )
        }
        val h = holder(privacyApi = privacyApi, scope = backgroundScope)
        runCurrent()

        h.exportSelf()

        val flow = h.state.value.exportFlow
        assertTrue(flow is ExportFlow.Failed)
        assertEquals("You've reached today's export limit — please try again tomorrow.", (flow as ExportFlow.Failed).message)
    }

    @Test
    fun `dismissExportResult resets the export flow to Idle`() = runTest {
        val h = holder(scope = backgroundScope)
        runCurrent()
        h.exportSelf()

        h.dismissExportResult()

        assertEquals(ExportFlow.Idle, h.state.value.exportFlow)
    }

    // ------------------------------------------------------------------
    // Delete account — two-step gating (specs/003 §12.4 test-checklist: "no call before the
    // second confirm")
    // ------------------------------------------------------------------

    @Test
    fun `startDeleteAccount enters Step1Confirming without any network call`() = runTest {
        val privacyApi = FakePrivacyApi()
        val h = holder(privacyApi = privacyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()

        assertTrue(h.state.value.deleteAccountFlow is DeleteAccountFlow.Step1Confirming)
        assertEquals(0, privacyApi.deleteAccountCallCount)
    }

    @Test
    fun `advancing to Step2Confirming still makes no network call`() = runTest {
        val privacyApi = FakePrivacyApi()
        val h = holder(privacyApi = privacyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()
        h.advanceDeleteAccountConfirmation()

        assertTrue(h.state.value.deleteAccountFlow is DeleteAccountFlow.Step2Confirming)
        assertEquals(0, privacyApi.deleteAccountCallCount)
    }

    @Test
    fun `confirmDeleteAccount before reaching Step2Confirming is a no-op`() = runTest {
        val privacyApi = FakePrivacyApi()
        val h = holder(privacyApi = privacyApi, scope = backgroundScope)
        runCurrent()

        h.confirmDeleteAccount() // Idle -> ignored
        h.startDeleteAccount()
        h.confirmDeleteAccount() // Step1Confirming -> ignored

        assertEquals(0, privacyApi.deleteAccountCallCount)
    }

    @Test
    fun `Step1Confirming carries the cascade warning when the caller is the sole parent`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()

        val step1 = h.state.value.deleteAccountFlow as DeleteAccountFlow.Step1Confirming
        assertTrue(step1.cascadeWarning)
    }

    @Test
    fun `Step1Confirming carries no cascade warning for a co-parent`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, coParent), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()

        val step1 = h.state.value.deleteAccountFlow as DeleteAccountFlow.Step1Confirming
        assertFalse(step1.cascadeWarning)
    }

    @Test
    fun `cancelDeleteAccount returns to Idle from any step`() = runTest {
        val h = holder(scope = backgroundScope)
        runCurrent()
        h.startDeleteAccount()
        h.advanceDeleteAccountConfirmation()

        h.cancelDeleteAccount()

        assertEquals(DeleteAccountFlow.Idle, h.state.value.deleteAccountFlow)
    }

    @Test
    fun `confirmDeleteAccount from Step2Confirming makes exactly one call, then deletes Firebase, wipes state, and signs out`() = runTest {
        val privacyApi = FakePrivacyApi()
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-parent"))
        val localStateWiper = FakeLocalStateWiper()
        val h = holder(privacyApi = privacyApi, authProvider = authProvider, localStateWiper = localStateWiper, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()
        h.advanceDeleteAccountConfirmation()
        h.confirmDeleteAccount()

        assertEquals(1, privacyApi.deleteAccountCallCount)
        assertEquals(1, authProvider.deleteCurrentUserCallCount)
        assertEquals(listOf("uid-parent"), localStateWiper.wipeAllCalls)
        assertEquals(1, authProvider.signOutCallCount)
        assertEquals(DeleteAccountFlow.Idle, h.state.value.deleteAccountFlow)
    }

    @Test
    fun `backend deleteAccount failure surfaces a user message and never touches Firebase or local state`() = runTest {
        val privacyApi = FakePrivacyApi().apply {
            deleteAccountResult = ApiResult.Failure(ApiError.InternalError("boom", "r_3"))
        }
        val authProvider = FakeAuthProvider()
        val localStateWiper = FakeLocalStateWiper()
        val h = holder(privacyApi = privacyApi, authProvider = authProvider, localStateWiper = localStateWiper, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()
        h.advanceDeleteAccountConfirmation()
        h.confirmDeleteAccount()

        val flow = h.state.value.deleteAccountFlow
        assertTrue(flow is DeleteAccountFlow.Failed)
        assertEquals(0, authProvider.deleteCurrentUserCallCount)
        assertTrue(localStateWiper.wipeAllCalls.isEmpty())
        assertEquals(0, authProvider.signOutCallCount)
    }

    @Test
    fun `a Firebase delete failure after a successful 204 offers a retry path without wiping state`() = runTest {
        val privacyApi = FakePrivacyApi()
        val authProvider = FakeAuthProvider().apply { deleteCurrentUserResult = false }
        val localStateWiper = FakeLocalStateWiper()
        val h = holder(privacyApi = privacyApi, authProvider = authProvider, localStateWiper = localStateWiper, scope = backgroundScope)
        runCurrent()

        h.startDeleteAccount()
        h.advanceDeleteAccountConfirmation()
        h.confirmDeleteAccount()

        assertEquals(DeleteAccountFlow.FirebaseRetryNeeded, h.state.value.deleteAccountFlow)
        assertEquals(1, privacyApi.deleteAccountCallCount)
        assertTrue(localStateWiper.wipeAllCalls.isEmpty())
        assertEquals(0, authProvider.signOutCallCount)
    }

    @Test
    fun `retryFirebaseDelete retries only the Firebase step, never re-calling DELETE users me`() = runTest {
        val privacyApi = FakePrivacyApi()
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-parent")).apply { deleteCurrentUserResult = false }
        val localStateWiper = FakeLocalStateWiper()
        val h = holder(privacyApi = privacyApi, authProvider = authProvider, localStateWiper = localStateWiper, scope = backgroundScope)
        runCurrent()
        h.startDeleteAccount()
        h.advanceDeleteAccountConfirmation()
        h.confirmDeleteAccount()
        assertEquals(DeleteAccountFlow.FirebaseRetryNeeded, h.state.value.deleteAccountFlow)

        authProvider.deleteCurrentUserResult = true
        h.retryFirebaseDelete()

        assertEquals(1, privacyApi.deleteAccountCallCount) // still just the one original call
        assertEquals(2, authProvider.deleteCurrentUserCallCount)
        assertEquals(listOf("uid-parent"), localStateWiper.wipeAllCalls)
        assertEquals(1, authProvider.signOutCallCount)
        assertEquals(DeleteAccountFlow.Idle, h.state.value.deleteAccountFlow)
    }

    @Test
    fun `retryFirebaseDelete outside FirebaseRetryNeeded is a no-op`() = runTest {
        val authProvider = FakeAuthProvider()
        val h = holder(authProvider = authProvider, scope = backgroundScope)
        runCurrent()

        h.retryFirebaseDelete()

        assertEquals(0, authProvider.deleteCurrentUserCallCount)
    }

    // ------------------------------------------------------------------
    // Delete family — parent-only, typed-name gating (008 §5.4)
    // ------------------------------------------------------------------

    @Test
    fun `startDeleteFamily is a no-op for a non-parent`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember, meIndex = 1), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteFamily()

        assertEquals(DeleteFamilyFlow.Idle, h.state.value.deleteFamilyFlow)
    }

    @Test
    fun `startDeleteFamily for a parent enters Confirming prefilled with the family name`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteFamily()

        val confirming = h.state.value.deleteFamilyFlow as DeleteFamilyFlow.Confirming
        assertEquals("Wauters", confirming.familyName)
        assertEquals("", confirming.typedName)
    }

    @Test
    fun `confirmDeleteFamily with a mismatched typed name makes no network call`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val privacyApi = FakePrivacyApi()
        val h = holder(privacyApi = privacyApi, familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteFamily()
        h.updateDeleteFamilyTypedName("not the family name")
        h.confirmDeleteFamily()

        assertEquals(0, privacyApi.deleteFamilyCallCount)
        assertTrue(h.state.value.deleteFamilyFlow is DeleteFamilyFlow.Confirming)
    }

    @Test
    fun `confirmDeleteFamily with a matching typed name calls deleteFamily exactly once and returns to family-less state on success`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val privacyApi = FakePrivacyApi()
        val h = holder(privacyApi = privacyApi, familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteFamily()
        h.updateDeleteFamilyTypedName("Wauters")
        h.confirmDeleteFamily()

        assertEquals(1, privacyApi.deleteFamilyCallCount)
        assertEquals(DeleteFamilyFlow.Idle, h.state.value.deleteFamilyFlow)
        assertFalse(h.state.value.isParent)
        assertEquals(null, h.state.value.familyName)
    }

    @Test
    fun `confirmDeleteFamily failure surfaces a user message and leaves family state untouched`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val privacyApi = FakePrivacyApi().apply {
            deleteFamilyResult = ApiResult.Failure(ApiError.InternalError("boom", "r_4"))
        }
        val h = holder(privacyApi = privacyApi, familyApi = familyApi, scope = backgroundScope)
        runCurrent()

        h.startDeleteFamily()
        h.updateDeleteFamilyTypedName("Wauters")
        h.confirmDeleteFamily()

        val flow = h.state.value.deleteFamilyFlow
        assertTrue(flow is DeleteFamilyFlow.Failed)
        assertTrue(h.state.value.isParent)
    }

    @Test
    fun `cancelDeleteFamily returns to Idle`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(familyOf(soleParent, plainMember), defaultFeatures())
        }
        val h = holder(familyApi = familyApi, scope = backgroundScope)
        runCurrent()
        h.startDeleteFamily()

        h.cancelDeleteFamily()

        assertEquals(DeleteFamilyFlow.Idle, h.state.value.deleteFamilyFlow)
    }
}
