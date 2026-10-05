package com.findly.android.ui.groups

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupMemberLocationDto
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import com.findly.android.ui.map.CameraCommand
import com.findly.android.ui.map.CameraPolicyState
import com.findly.android.ui.map.MapCamera
import com.findly.android.ui.map.MapCameraPolicy
import com.findly.android.ui.map.MapCameraTarget
import com.findly.android.ui.map.MapRefreshController
import com.findly.android.ui.map.RefreshRun
import com.findly.android.ui.map.RefreshTrigger
import com.findly.android.ui.map.fetchGuarded
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The group-map screen's pure state machine (001-api-contract.md §12.10). Constructor-injected
 * [CoroutineScope] — mirrors [com.findly.android.ui.map.MapStateHolder]'s exact shape
 * (specs/003-android-client.md §12.2: "`GroupMapStateHolder` polls ... the same way
 * `MapStateHolder` treats the family map").
 *
 * **Data freshness (specs/010 §3.6, which §3.2 extends to this screen; row A55).** Exactly the
 * family map's rules, through the same pure [MapRefreshController]: an eager `init` load, a
 * re-fetch on every return to visible + foregrounded ([onVisible]/[onHidden]), every 30 s while
 * visible, never in the background, one request in flight, a failed periodic refresh keeps the last
 * roster silently, and a response is merged into the *latest* state (a member selected mid-fetch
 * survives it) — see [com.findly.android.ui.map.MapStateHolder]'s class doc for the reasoning. The
 * group map's **confirmed state changes** (010 §3.6) are not failed refreshes, whatever triggered
 * them: `PROFILE_NOT_FOUND` → [GroupMapUiState.RouteToOnboarding], `GROUP_EXPIRED` →
 * [GroupMapUiState.Expired], `GROUP_NOT_FOUND` (a removed member, a deleted or swept group) → the
 * first-load [GroupMapUiState.Error] — each also **ends polling** ([MapRefreshController.endPolling]),
 * so a kicked member never watches a frozen roster.
 */
class GroupMapStateHolder(
    private val groupId: String,
    private val groupsApi: GroupsApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<GroupMapUiState>(GroupMapUiState.Loading)
    val state: StateFlow<GroupMapUiState> = _state.asStateFlow()

    // specs/010-app-shell-and-screen-ux.md §3.2/§3.4: the same camera policy state the family map
    // keeps, through the same renderer seam.
    private var cameraPolicyState = CameraPolicyState.INITIAL
    private var cameraSeq = 0L

    private val refreshController = MapRefreshController(scope, fetch = ::fetchRoster)

    init {
        refreshController.start()
    }

    /** specs/010 §3.6 / §3.2: the group map became visible **and** foregrounded. */
    fun onVisible() = refreshController.onVisible()

    /** specs/010 §3.6: stops the 30 s timer — nothing is fetched in the background. */
    fun onHidden() = refreshController.onHidden()

    /** The user's own Refresh / Retry — see [com.findly.android.ui.map.MapStateHolder.refresh]. */
    suspend fun refresh() {
        refreshController.request(RefreshTrigger.Explicit)
    }

    private suspend fun fetchRoster(run: RefreshRun) {
        if (run.explicit) {
            val current = _state.value
            if (current is GroupMapUiState.Content) {
                _state.value = current.copy(isRefreshing = true)
            }
        }
        when (val result = fetchGuarded { groupsApi.getGroupLatestLocations(groupId) }) {
            is ApiResult.Success -> applyRoster(result.data.members.map { it.toUi() })
            is ApiResult.Failure -> applyFailure(result.error, explicit = run.explicit)
        }
    }

    private fun applyRoster(members: List<GroupMapMemberUi>) {
        // The state as it is NOW, after the request — never a snapshot from when it started (see
        // MapStateHolder's class doc: a selection made while the fetch was in flight must survive).
        val latest = _state.value as? GroupMapUiState.Content
        val points = members.locatedPoints()

        // Not Content == the map surface is not on screen (Loading, or an Error card that replaced
        // the GoogleMap and tore it out of composition): this success opens a FRESH map surface, so
        // it is a first load of that surface — the camera policy re-runs for it, and the selection
        // is gone with the sheet (A55 review F1; see MapStateHolder.applyRoster).
        val freshSurface = latest == null

        val shouldRun = freshSurface ||
            MapCameraPolicy.shouldRunOnLoadOrRefresh(cameraPolicyState, points.isNotEmpty())
        cameraPolicyState = MapCameraPolicy.nextState(cameraPolicyState, points.isNotEmpty())
        val cameraCommand = if (shouldRun) nextCameraCommand(MapCamera.target(points)) else latest?.cameraCommand

        val selected = latest?.selectedUserId?.takeIf { id -> members.any { it.userId == id } }
        _state.value = GroupMapUiState.Content(
            members = members,
            selectedUserId = selected,
            cameraCommand = cameraCommand,
        )
    }

    private fun applyFailure(error: ApiError, explicit: Boolean) {
        // specs/010 §2.1: group screens only need a profile, so only PROFILE_NOT_FOUND routes here
        // (familyScoped = false, as in GroupsListStateHolder).
        val variant = ProfileDeadEndRouting.classify(error, familyScoped = false)
        val confirmedStateChange =
            variant != null || error is ApiError.GroupExpired || error is ApiError.GroupNotFound
        // 010 §3.6: a confirmed state change is not a failed refresh — it routes/surfaces exactly as
        // on a first load, whichever trigger saw it, AND ends polling for this screen.
        if (confirmedStateChange) refreshController.endPolling()

        val latest = _state.value
        _state.value = when {
            variant != null -> GroupMapUiState.RouteToOnboarding(variant)
            // GROUP_EXPIRED: surfaces (and bounces the user to the groups list).
            error is ApiError.GroupExpired -> GroupMapUiState.Expired()
            // GROUP_NOT_FOUND (a removed member — non-membership is masked as 404, 001 §12 — or a
            // deleted/swept group): the first-load error state, never a silently frozen roster.
            error is ApiError.GroupNotFound -> GroupMapUiState.Error(error.userMessage())
            // specs/010 §3.6: a periodic/foreground refresh that fails keeps the last data, no
            // error surface. Only the first load (no content yet) or an explicit Refresh reports.
            latest is GroupMapUiState.Content && !explicit -> latest.copy(isRefreshing = false)
            else -> GroupMapUiState.Error(error.userMessage())
        }
    }

    /** specs/010 §3.5, position-only mirror of [com.findly.android.ui.map.MapStateHolder.selectMember]
     * — there is exactly one point per member here, so selection targets it directly rather than
     * resolving a freshest device first. */
    fun selectMember(userId: String) {
        val current = _state.value as? GroupMapUiState.Content ?: return
        if (current.selectedUserId == userId) {
            _state.value = current.copy(selectedUserId = null)
            return
        }
        val member = current.members.firstOrNull { it.userId == userId } ?: return
        val cameraCommand = if (member.hasLocation) {
            nextCameraCommand(MapCameraTarget.Center(member.lat!!, member.lon!!, MapCamera.SINGLE_POINT_ZOOM))
        } else {
            current.cameraCommand
        }
        _state.value = current.copy(selectedUserId = userId, cameraCommand = cameraCommand)
    }

    /** specs/010 §3.5: tapping the map background deselects, without moving the camera. */
    fun deselect() {
        val current = _state.value as? GroupMapUiState.Content ?: return
        if (current.selectedUserId != null) {
            _state.value = current.copy(selectedUserId = null)
        }
    }

    /** specs/010 §3.4's explicit fit-all action: re-runs [MapCamera.target] over the currently
     * loaded points, unconditionally. */
    fun fitAll() {
        val current = _state.value as? GroupMapUiState.Content ?: return
        _state.value = current.copy(cameraCommand = nextCameraCommand(MapCamera.target(current.members.locatedPoints())))
    }

    private fun nextCameraCommand(target: MapCameraTarget): CameraCommand {
        cameraSeq += 1
        return CameraCommand(cameraSeq, target)
    }
}

private fun List<GroupMapMemberUi>.locatedPoints(): List<Pair<Double, Double>> =
    filter { it.hasLocation }.map { it.lat!! to it.lon!! }

private fun GroupMemberLocationDto.toUi(): GroupMapMemberUi = GroupMapMemberUi(
    userId = userId,
    displayName = displayName,
    role = role,
    lat = location?.lat,
    lon = location?.lon,
    accuracyM = location?.accuracyM,
    recordedAt = location?.recordedAt,
    isStale = location?.isStale,
)
