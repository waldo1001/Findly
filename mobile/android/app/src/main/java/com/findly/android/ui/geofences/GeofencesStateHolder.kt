package com.findly.android.ui.geofences

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GeofenceDto
import com.findly.android.network.ports.GeofenceApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The geofence editor's pure state machine (001-api-contract.md §7.1/§7.2). Constructor-injected
 * [CoroutineScope] — same pattern as [com.findly.android.ui.home.HomeStateHolder]/
 * [com.findly.android.ui.map.MapStateHolder]. [GeofencesViewModel] is the thin `ViewModel`
 * wrapper.
 */
class GeofencesStateHolder(
    private val geofenceApi: GeofenceApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<GeofencesUiState>(GeofencesUiState.Loading)
    val state: StateFlow<GeofencesUiState> = _state.asStateFlow()

    init {
        scope.launch { load() }
    }

    /** Unconditional `GET /geofences` (no `If-None-Match`), so a `304`/`null` body never occurs
     * here — only [save]'s conflict path re-fetches conditionally-adjacent state. */
    suspend fun load() {
        _state.value = GeofencesUiState.Loading
        when (val result = geofenceApi.getGeofences()) {
            is ApiResult.Success -> {
                val etagged = result.data
                if (etagged != null) {
                    _state.value = GeofencesUiState.Content(
                        geofences = etagged.value.geofences.map { it.toUi() },
                        etag = etagged.etag,
                    )
                }
            }
            is ApiResult.Failure -> {
                // specs/010-app-shell-and-screen-ux.md §2.1: GET /geofences is family-scoped
                // (001 §1.6 — "member") — this was the field-reported dead-end screen (2026-08-26).
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = true)
                _state.value = if (variant != null) {
                    GeofencesUiState.RouteToOnboarding(variant)
                } else {
                    GeofencesUiState.Error(result.error.userMessage())
                }
            }
        }
    }

    /** Client-side mirror of 001 §7.2's validation (name 1–50 chars, `radiusM` ∈ [100, 5000]) so
     * the editor can surface a problem before a round trip; the server re-validates regardless
     * and remains the source of truth. Returns a user-facing message, or `null` if valid. */
    fun validate(draft: GeofenceUi): String? = when {
        draft.name.isBlank() || draft.name.length > 50 -> "Name must be 1-50 characters"
        draft.radiusM < 100.0 || draft.radiusM > 5000.0 -> "Radius must be between 100 and 5000 meters"
        else -> null
    }

    /** Adds a new geofence or updates an existing one (matched by `geofenceId`) in the local
     * pending list — a client-only edit; call [save] to persist it (§7.2 is a full-document
     * `PUT`, there is no per-geofence endpoint). No-op if [load] hasn't produced [GeofencesUiState.Content]
     * yet. */
    fun upsertGeofence(draft: GeofenceUi) {
        val current = _state.value as? GeofencesUiState.Content ?: return
        val updated = current.geofences.filterNot { it.geofenceId == draft.geofenceId } + draft
        _state.value = current.copy(geofences = updated, saveError = null)
    }

    fun removeGeofence(geofenceId: String) {
        val current = _state.value as? GeofencesUiState.Content ?: return
        _state.value = current.copy(
            geofences = current.geofences.filterNot { it.geofenceId == geofenceId },
            saveError = null,
        )
    }

    /**
     * Full-document replace (§7.2), `If-Match: <etag>`. On success, replaces state with the
     * server's stored copy (new version + etag). On `409 GEOFENCE_VERSION_CONFLICT`, re-fetches
     * the fresh server copy for its etag and adopts it as the new baseline while **keeping the
     * caller's pending edit** — this is the "re-fetch + merge UX": the user's in-progress edit is
     * never silently discarded, they just need to hit save again (now against the current
     * version) — see [GeofencesUiState.Content.conflict].
     */
    suspend fun save() {
        val current = _state.value as? GeofencesUiState.Content ?: return
        _state.value = current.copy(isSaving = true, saveError = null)

        when (val result = geofenceApi.replaceGeofences(current.etag, current.geofences.map { it.toDto() })) {
            is ApiResult.Success -> {
                val etagged = result.data
                _state.value = GeofencesUiState.Content(
                    geofences = etagged.value.geofences.map { it.toUi() },
                    etag = etagged.etag,
                )
            }
            is ApiResult.Failure -> {
                val error = result.error
                if (error is ApiError.GeofenceVersionConflict) {
                    reconcileConflict(current)
                } else {
                    _state.value = current.copy(isSaving = false, saveError = error.userMessage())
                }
            }
        }
    }

    private suspend fun reconcileConflict(pending: GeofencesUiState.Content) {
        when (val refreshed = geofenceApi.getGeofences()) {
            is ApiResult.Success -> {
                val etagged = refreshed.data
                if (etagged == null) {
                    _state.value = pending.copy(isSaving = false, saveError = "Couldn't refresh after conflict")
                } else {
                    _state.value = pending.copy(
                        etag = etagged.etag,
                        isSaving = false,
                        conflict = true,
                        saveError = null,
                    )
                }
            }
            is ApiResult.Failure -> _state.value = pending.copy(
                isSaving = false,
                saveError = refreshed.error.userMessage(),
            )
        }
    }
}

private fun GeofenceDto.toUi(): GeofenceUi = GeofenceUi(
    geofenceId = geofenceId,
    name = name,
    lat = lat,
    lon = lon,
    radiusM = radiusM,
    icon = icon,
    notifyOnEnter = notifyOnEnter,
    notifyOnExit = notifyOnExit,
)

private fun GeofenceUi.toDto(): GeofenceDto = GeofenceDto(
    geofenceId = geofenceId,
    name = name,
    lat = lat,
    lon = lon,
    radiusM = radiusM,
    icon = icon,
    notifyOnEnter = notifyOnEnter,
    notifyOnExit = notifyOnExit,
)
