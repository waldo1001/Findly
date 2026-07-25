package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.ExportResult
import com.findly.android.network.ports.PrivacyApi

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Used by
 * [com.findly.android.ui.settings.PrivacyStateHolder]'s tests (specs/003-android-client.md §12.4). */
class FakePrivacyApi : PrivacyApi {
    val exportDataCalls = mutableListOf<String?>()
    var deleteAccountCallCount = 0
        private set
    var deleteFamilyCallCount = 0
        private set

    var exportDataResult: ApiResult<ExportResult> = ApiResult.Success(
        ExportResult(
            body = "{\"formatVersion\":1}".toByteArray(Charsets.UTF_8),
            suggestedFileName = "findly-export-uid-test-2026-07-25.json",
            contentType = "application/json; charset=utf-8",
        ),
        features = null,
    )

    var deleteAccountResult: ApiResult<Unit> = ApiResult.Success(Unit, features = null)
    var deleteFamilyResult: ApiResult<Unit> = ApiResult.Success(Unit, features = null)

    override suspend fun exportData(userId: String?): ApiResult<ExportResult> {
        exportDataCalls.add(userId)
        return exportDataResult
    }

    override suspend fun deleteAccount(): ApiResult<Unit> {
        deleteAccountCallCount++
        return deleteAccountResult
    }

    override suspend fun deleteFamily(): ApiResult<Unit> {
        deleteFamilyCallCount++
        return deleteFamilyResult
    }
}
