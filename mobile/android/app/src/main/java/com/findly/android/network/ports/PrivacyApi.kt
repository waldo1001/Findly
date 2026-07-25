package com.findly.android.network.ports

import com.findly.android.network.ApiResult
import com.findly.android.network.ExportResult

/**
 * 001-api-contract.md §13 — Privacy: export & deletion (specs/008-privacy-endpoints.md; client
 * obligations specs/003-android-client.md §12.4).
 */
interface PrivacyApi {

    /**
     * `GET /export` (§13.1) — the one **unenveloped** response in the API; [userId] optionally
     * names another current member of the caller's family (parent-only, defaults to the caller
     * when `null`). The raw body is handed to the OS share/save sheet un-parsed — never decoded
     * beyond the HTTP layer (specs/003 §12.4).
     */
    suspend fun exportData(userId: String? = null): ApiResult<ExportResult>

    /**
     * `DELETE /users/me` (§13.2) — bare `204`. Available to every authenticated user, including
     * one with no profile (idempotent no-op, 008 §4.1). Callers MUST call the Firebase SDK's
     * `currentUser.delete()` only after this returns success (008 §1.3).
     */
    suspend fun deleteAccount(): ApiResult<Unit>

    /** `DELETE /families/me` (§13.3, parent-only) — bare `204`. */
    suspend fun deleteFamily(): ApiResult<Unit>
}
