package com.findly.android.ui.geofences

/** A circular geofence (001-api-contract.md §7.1/§7.2). Used both for the read-only list entries
 * and as the add/edit form's draft shape — the two are identical on the wire. */
data class GeofenceUi(
    val geofenceId: String,
    val name: String,
    val lat: Double,
    val lon: Double,
    val radiusM: Double,
    val icon: String,
    val notifyOnEnter: Boolean,
    val notifyOnExit: Boolean,
)

/** State surfaced by [GeofencesStateHolder] (specs/003-android-client.md §12's reserved
 * `Geofences` destination, filled in by A2). */
sealed class GeofencesUiState {
    data object Loading : GeofencesUiState()
    data class Error(val message: String) : GeofencesUiState()

    /**
     * @property conflict `true` right after a `GEOFENCE_VERSION_CONFLICT` (409, §7.2) has been
     *   reconciled — [etag] is already the fresh server baseline and [geofences] is still the
     *   caller's pending (unsaved) edit, so the next [GeofencesStateHolder.save] call succeeds
     *   against the current version; the screen should show a "someone else changed this —
     *   review before saving again" banner while this is `true`.
     * @property saveError set on any other (non-conflict) [save][GeofencesStateHolder.save]
     *   failure; cleared on the next successful mutation.
     */
    data class Content(
        val geofences: List<GeofenceUi>,
        val etag: String,
        val isSaving: Boolean = false,
        val conflict: Boolean = false,
        val saveError: String? = null,
    ) : GeofencesUiState()
}
