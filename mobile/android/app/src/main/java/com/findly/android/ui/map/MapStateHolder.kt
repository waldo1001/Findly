package com.findly.android.ui.map

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestMemberDto
import com.findly.android.network.ports.LocationsApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The live-map screen's pure state machine (001-api-contract.md §5.2). Constructor-injected
 * [CoroutineScope] so tests supply a `TestScope`/`backgroundScope` — mirrors [HomeStateHolder]'s
 * pattern (specs/003-android-client.md §12/§14). [MapViewModel] is the thin `ViewModel` wrapper.
 *
 * **Data freshness (specs/010 §3.6, row A55).** WHEN the roster is fetched — first appearance, every
 * return to visible + foregrounded, every 30 s while visible, one request in flight — is the pure
 * [MapRefreshController]'s decision; this class supplies WHAT a fetch does with its response, and
 * the screen only reports visibility through [onVisible]/[onHidden]. Two rules ride on that:
 * - **Failure.** A periodic/foreground refresh that fails leaves the [MapUiState.Content] on
 *   screen untouched — no error surface; with no content yet (the first load failed) the
 *   [MapUiState.Error] state stays and the next tick retries; an explicit Refresh still reports
 *   its own failure. A confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` routes to Onboarding for
 *   *any* trigger (010 §2.1 — a confirmed state change, not a failed refresh).
 * - **Merge into the latest state.** A response is applied to `_state.value` as it is *when the
 *   response arrives*, never to a snapshot taken when the request started. With a background timer
 *   a request is routinely in flight when the user taps a member; a stale snapshot would erase that
 *   selection and swap its camera command for an older one, which the renderer would replay.
 */
class MapStateHolder(
    private val locationsApi: LocationsApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<MapUiState>(MapUiState.Loading)
    val state: StateFlow<MapUiState> = _state.asStateFlow()

    // specs/010-app-shell-and-screen-ux.md §3.4: WHEN the camera re-runs, tracked as pure state
    // across this holder's lifetime (see MapCameraPolicy's doc) — never on an ordinary refresh,
    // except the one carve-out the spec grants (a zero-point open's first-ever point arrival).
    private var cameraPolicyState = CameraPolicyState.INITIAL
    private var cameraSeq = 0L

    private val refreshController = MapRefreshController(scope, fetch = ::fetchRoster)

    init {
        refreshController.start()
    }

    /** specs/010 §3.6: the map became visible **and** foregrounded (its destination is the top of
     * the stack and the activity is resumed). */
    fun onVisible() = refreshController.onVisible()

    /** specs/010 §3.6: the map stopped being visible or the app left the foreground — stops the
     * 30 s timer; nothing is fetched in the background. */
    fun onHidden() = refreshController.onHidden()

    /** The user's own Refresh / Retry (§5.2 — one call, one partition scan server-side). Public so
     * the screen's refresh/retry action can call it directly. Dropped, but adopting the running
     * fetch, if one is already in flight (010 §3.6 — see [MapRefreshController.request]). */
    suspend fun refresh() {
        refreshController.request(RefreshTrigger.Explicit)
    }

    private suspend fun fetchRoster(run: RefreshRun) {
        if (run.explicit) {
            val current = _state.value
            if (current is MapUiState.Content) {
                _state.value = current.copy(isRefreshing = true)
            }
        }
        when (val result = fetchGuarded { locationsApi.getLatestLocations() }) {
            is ApiResult.Success -> applyRoster(result.data.members.map { it.toUi() })
            is ApiResult.Failure -> applyFailure(result.error, explicit = run.explicit)
        }
    }

    private fun applyRoster(members: List<RosterMemberUi>) {
        // The state as it is NOW, after the request — see the class doc ("merge into the latest").
        val latest = _state.value as? MapUiState.Content
        val points = members.locatedPoints()

        // A state that is not Content means the map surface is not on screen: Loading (nothing yet)
        // or Error/RouteToOnboarding, where the Error card replaced the GoogleMap and tore it out of
        // composition. This success therefore opens a FRESH map surface at the default camera, so
        // it is a first load of that surface (010 §3.4 trigger 1) — without this the camera policy
        // (which says "never on an ordinary refresh") would leave it unfitted, with the selection
        // gone with the sheet (A55 review F1).
        val freshSurface = latest == null

        // specs/010-app-shell-and-screen-ux.md §3.4: decide WHETHER this load/refresh re-runs the
        // camera policy — never on an ordinary refresh, with the one carve-out MapCameraPolicy
        // itself documents.
        val shouldRun = freshSurface ||
            MapCameraPolicy.shouldRunOnLoadOrRefresh(cameraPolicyState, points.isNotEmpty())
        cameraPolicyState = MapCameraPolicy.nextState(cameraPolicyState, points.isNotEmpty())
        val cameraCommand = if (shouldRun) nextCameraCommand(MapCamera.target(points)) else latest?.cameraCommand

        val selected = latest?.selectedUserId?.takeIf { id -> members.any { it.userId == id } }
        _state.value = MapUiState.Content(
            members = members,
            selectedUserId = selected,
            cameraCommand = cameraCommand,
        )
    }

    private fun applyFailure(error: ApiError, explicit: Boolean) {
        // specs/010-app-shell-and-screen-ux.md §2.1: GET /locations/latest is family-scoped
        // (001 §1.6 — "member") — a confirmed PROFILE_NOT_FOUND/FAMILY_NOT_FOUND routes to
        // Onboarding instead of the dead-end retryable card, whichever trigger saw it.
        val variant = ProfileDeadEndRouting.classify(error, familyScoped = true)
        // 010 §3.6: a confirmed state change is not a failed refresh — it routes as on a first load
        // AND ends polling (no timer tick or foreground return fetches again; the Map entry is
        // about to be popped anyway, this makes it true independently of when navigation lands).
        if (variant != null) refreshController.endPolling()
        val latest = _state.value
        _state.value = when {
            variant != null -> MapUiState.RouteToOnboarding(variant)
            // specs/010 §3.6: a periodic/foreground refresh that fails keeps the last data, no
            // error surface. Only the first load (no content yet) or an explicit Refresh reports.
            latest is MapUiState.Content && !explicit -> latest.copy(isRefreshing = false)
            else -> MapUiState.Error(error.userMessage())
        }
    }

    /** specs/010 §3.5: selects/deselects [userId], zooming to their freshest located device at
     * [MapCamera.SINGLE_POINT_ZOOM] when one exists; a member with no located device can still be
     * selected (row/marker highlight) but the camera MUST NOT move. Tapping the already-selected
     * member deselects (no camera move either way). */
    fun selectMember(userId: String) {
        val current = _state.value as? MapUiState.Content ?: return
        if (current.selectedUserId == userId) {
            _state.value = current.copy(selectedUserId = null)
            return
        }
        val member = current.members.firstOrNull { it.userId == userId } ?: return
        val freshest = MapCameraPolicy.freshestLocatedDevice(member.devices)
        val cameraCommand = freshest?.let { nextCameraCommand(MapCameraTarget.Center(it.lat!!, it.lon!!, MapCamera.SINGLE_POINT_ZOOM)) }
            ?: current.cameraCommand
        _state.value = current.copy(selectedUserId = userId, cameraCommand = cameraCommand)
    }

    /** specs/010 §3.5: tapping the map background deselects whatever member is currently
     * selected, without moving the camera — a no-op when nothing is selected. */
    fun deselect() {
        val current = _state.value as? MapUiState.Content ?: return
        if (current.selectedUserId != null) {
            _state.value = current.copy(selectedUserId = null)
        }
    }

    /** specs/010 §3.4's explicit fit-all action: re-runs [MapCamera.target] over the currently
     * loaded points, unconditionally (the one trigger that always runs regardless of policy
     * state). */
    fun fitAll() {
        val current = _state.value as? MapUiState.Content ?: return
        _state.value = current.copy(cameraCommand = nextCameraCommand(MapCamera.target(current.members.locatedPoints())))
    }

    private fun nextCameraCommand(target: MapCameraTarget): CameraCommand {
        cameraSeq += 1
        return CameraCommand(cameraSeq, target)
    }
}

private fun List<RosterMemberUi>.locatedPoints(): List<Pair<Double, Double>> =
    flatMap { member -> member.devices.filter { it.hasLocation }.map { it.lat!! to it.lon!! } }

private fun LatestMemberDto.toUi(): RosterMemberUi = RosterMemberUi(
    userId = userId,
    displayName = displayName,
    devices = devices.map { it.toUi() },
)

private fun LatestDeviceDto.toUi(): RosterDeviceUi = RosterDeviceUi(
    deviceId = deviceId,
    deviceName = deviceName,
    lat = lat,
    lon = lon,
    recordedAt = recordedAt,
    batteryPct = batteryPct,
    trackingEnabled = trackingEnabled,
    syncIntervalMinutes = syncIntervalMinutes,
    isStale = isStale,
)
