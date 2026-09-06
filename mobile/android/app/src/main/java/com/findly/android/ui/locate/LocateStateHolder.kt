package com.findly.android.ui.locate

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LastKnownDto
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LocateFixDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.ports.LocateApi
import com.findly.android.network.ports.LocationsApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private val NON_FULFILLED_TERMINAL_STATUSES = setOf("expired", "pushFailed")

/**
 * The "locate now" screen's pure state machine (001-api-contract.md §6). Constructor-injected
 * [CoroutineScope] (tests supply `backgroundScope`, same pattern as
 * [com.findly.android.ui.home.HomeStateHolder]) — its cancellation (e.g. `viewModelScope`
 * clearing) stops any in-flight poll loop automatically, nothing extra to clean up.
 * [pollIntervalMillis] defaults to the spec's 2 s (§6.2: "Clients SHOULD poll every 2 s until
 * terminal") but is overridable so tests don't need to wait on real wall-clock time — combined
 * with `kotlinx.coroutines.test`'s virtual time, [kotlinx.coroutines.delay] inside the poll loop
 * advances instantly under `runTest`.
 *
 * **specs/009-device-runtime.md §5.1 "Requester side" (amended 2026-09-06, A39, building on
 * B26).** Polling now stops at a terminal status **or `expiresAt`** — a `"fulfilled"` response is
 * definitive (rendered [LocateOutcome.FRESH] or [LocateOutcome.LATE] straight off the wire's
 * `late` field); anything else that ends the loop (`"expired"`, `"pushFailed"`, or [now] itself
 * reaching `expiresAt` while the server still says `"pending"`) triggers exactly one
 * `GET /locations/latest` fallback — [locationsApi] — before declaring
 * [LocateOutcome.UNREACHABLE]. If that call finds the target device's `recordedAt` newer than the
 * request's `createdAt`, the position is shown as [LocateOutcome.LATE] instead (a late fulfil, or
 * some other report, already updated last-known). [now] is injected (defaults to [Instant.now])
 * so the expiresAt-timeout path is deterministic under tests.
 */
class LocateStateHolder(
    private val locateApi: LocateApi,
    private val locationsApi: LocationsApi,
    private val scope: CoroutineScope,
    private val pollIntervalMillis: Long = 2000L,
    private val now: () -> Instant = Instant::now,
) {
    private val _state = MutableStateFlow<LocateUiState>(LocateUiState.Idle)
    val state: StateFlow<LocateUiState> = _state.asStateFlow()

    private var pollJob: Job? = null

    /** Exactly one of [targetUserId]/[targetDeviceId] (§6.1) — validated by
     * [com.findly.android.network.dto.CreateLocateRequestRequestDto.requireExactlyOneTarget]
     * inside the client, not re-validated here. Cancels any prior in-flight poll for this holder
     * before starting a new request. */
    fun requestLocate(targetUserId: String? = null, targetDeviceId: String? = null) {
        pollJob?.cancel()
        pollJob = scope.launch {
            when (val result = locateApi.createLocateRequest(targetUserId, targetDeviceId)) {
                is ApiResult.Success -> onCreated(result.data)
                is ApiResult.Failure -> _state.value = routeOrError(result.error)
            }
        }
    }

    /** Cancels an in-flight poll loop (e.g. the user navigates away). */
    fun cancelPolling() {
        pollJob?.cancel()
    }

    private suspend fun onCreated(dto: LocateRequestDto) {
        val lastKnown = dto.lastKnown?.toUi()
        // §6.1: the create response is only ever "pending" or, immediately, "pushFailed" (no
        // valid token to send to) - it never carries a fix, so a "pushFailed" here takes the same
        // fallback path any other non-fresh terminal does rather than being assumed unreachable.
        if (dto.status in NON_FULFILLED_TERMINAL_STATUSES) {
            _state.value = resolveViaFallback(dto.requestId, dto.targetDeviceId, dto.createdAt, lastKnown, statusOverride = dto.status)
            return
        }
        _state.value = LocateUiState.Polling(dto.requestId, lastKnown, dto.expiresAt)
        // Code-review fix (finding 6, A39 review, specs/009 §5.1 amended): the poll timeout is
        // captured once here, right as the create response is received - see pollWindowFor's doc.
        val receivedAt = now()
        val pollWindow = pollWindowFor(dto.createdAt, dto.expiresAt)
        pollUntilTerminal(dto.requestId, dto.targetDeviceId, dto.createdAt, receivedAt, pollWindow)
    }

    private suspend fun pollUntilTerminal(
        requestId: String,
        targetDeviceId: String,
        createdAt: String,
        receivedAt: Instant,
        pollWindow: Duration?,
    ) {
        while (true) {
            delay(pollIntervalMillis)
            when (val result = locateApi.getLocateRequest(requestId)) {
                is ApiResult.Success -> {
                    val dto = result.data
                    val lastKnown = (_state.value as? LocateUiState.Polling)?.lastKnown
                    when {
                        dto.status == "fulfilled" -> {
                            _state.value = LocateUiState.Terminal(
                                requestId = dto.requestId,
                                status = dto.status,
                                outcome = if (dto.late) LocateOutcome.LATE else LocateOutcome.FRESH,
                                fix = dto.fix?.toUi(),
                                lastKnown = lastKnown,
                            )
                            return
                        }

                        dto.status in NON_FULFILLED_TERMINAL_STATUSES || hasElapsedPollWindow(receivedAt, pollWindow) -> {
                            _state.value = resolveViaFallback(dto.requestId, targetDeviceId, createdAt, lastKnown, statusOverride = dto.status)
                            return
                        }

                        else -> {
                            _state.value = LocateUiState.Polling(dto.requestId, lastKnown, dto.expiresAt)
                        }
                    }
                }

                is ApiResult.Failure -> {
                    _state.value = routeOrError(result.error)
                    return
                }
            }
        }
    }

    /** specs/009 §5.1 (amended 2026-09-06, A39's review, finding 6): the poll timeout is the
     * server-computed window between its own `createdAt`/`expiresAt` pair — never compared as an
     * absolute instant against [now]. A client clock that runs slow is harmless (the server's own
     * lazy expiry already resolves to a terminal "expired" first); one that runs fast used to
     * satisfy `now() >= expiresAt` on the very first poll tick and report UNREACHABLE before the
     * target could possibly have answered. Returns `null` (never expires locally) if either
     * timestamp fails to parse — the loop then only ever ends via an explicit terminal status or a
     * poll failure, same as before this fix for a malformed response.
     *
     * **A39's final round, finding 2 (Minor):** a zero-length window (`createdAt == expiresAt`) is
     * malformed data, not a legitimately already-expired request, and must be treated the same as
     * an unparseable timestamp — `takeIf { it > Duration.ZERO }` (not `!it.isNegative`) so
     * `Duration.ZERO` also returns `null` instead of satisfying `hasElapsedPollWindow` on the very
     * first poll tick. */
    private fun pollWindowFor(createdAt: String, expiresAt: String): Duration? {
        val created = parseInstantOrNull(createdAt) ?: return null
        val expires = parseInstantOrNull(expiresAt) ?: return null
        val window = Duration.between(created, expires)
        return window.takeIf { it > Duration.ZERO }
    }

    /** Both readings come from the same [now] clock, so a constant skew in that clock cancels out
     * of this subtraction — only the *locally elapsed* duration since [receivedAt] matters. */
    private fun hasElapsedPollWindow(receivedAt: Instant, pollWindow: Duration?): Boolean {
        if (pollWindow == null) return false
        return Duration.between(receivedAt, now()) >= pollWindow
    }

    /** specs/009 §5.1 "Requester side": the one-shot `GET /locations/latest` check performed
     * before ever declaring [LocateOutcome.UNREACHABLE] — a `recordedAt` newer than [createdAt]
     * for [targetDeviceId] is shown as [LocateOutcome.LATE] instead. [statusOverride] preserves
     * the raw wire status that triggered the fallback ("expired"/"pushFailed"/"pending" on a
     * client-side timeout) for the UI's own copy; defaults to "expired" for the timeout case
     * (no server response ever confirmed a status). */
    private suspend fun resolveViaFallback(
        requestId: String,
        targetDeviceId: String,
        createdAt: String,
        lastKnown: LastKnownUi?,
        statusOverride: String = "expired",
    ): LocateUiState.Terminal {
        val createdAtInstant = parseInstantOrNull(createdAt)
        val latestResult = locationsApi.getLatestLocations()
        val device = (latestResult as? ApiResult.Success)?.data
            ?.members?.asSequence()?.flatMap { it.devices.asSequence() }
            ?.firstOrNull { it.deviceId == targetDeviceId }
        val recordedAt = device?.recordedAt?.let(::parseInstantOrNull)
        // Code-review fix (finding 13, A39 review): the outcome must not be fixed at LATE off
        // recordedAt alone - toFixUi() (below) returns null when lat/lon are absent, which used to
        // still produce Terminal(outcome = LATE, fix = null); the screen then falls back to
        // lastKnown and silently drops the age caption, showing a stale position under a "Located"
        // chip. Computing the fix first and requiring it non-null keeps LATE and a usable fix in
        // lockstep.
        val fix = device?.toFixUi()

        return if (createdAtInstant != null && recordedAt != null && recordedAt.isAfter(createdAtInstant) && fix != null) {
            LocateUiState.Terminal(
                requestId = requestId,
                status = statusOverride,
                outcome = LocateOutcome.LATE,
                fix = fix,
                lastKnown = lastKnown,
            )
        } else {
            LocateUiState.Terminal(
                requestId = requestId,
                status = statusOverride,
                outcome = LocateOutcome.UNREACHABLE,
                fix = null,
                lastKnown = lastKnown,
            )
        }
    }

    /** specs/010-app-shell-and-screen-ux.md §2.1: `POST /locate-requests`/`GET /locate-requests/{id}`
     * are family-scoped (001 §1.6 — "member") — Locate has no separate eager load, so this create/
     * poll call *is* its load path for the purposes of the routing rule. */
    private fun routeOrError(error: ApiError): LocateUiState {
        val variant = ProfileDeadEndRouting.classify(error, familyScoped = true)
        return if (variant != null) LocateUiState.RouteToOnboarding(variant) else LocateUiState.Error(error.userMessage())
    }

    private fun parseInstantOrNull(iso: String): Instant? = try {
        Instant.parse(iso)
    } catch (e: Exception) {
        null
    }
}

private fun LastKnownDto.toUi(): LastKnownUi = LastKnownUi(deviceId, lat, lon, accuracyM, recordedAt)

private fun LocateFixDto.toUi(): LocateFixUi = LocateFixUi(deviceId, lat, lon, accuracyM, recordedAt, batteryPct)

private fun LatestDeviceDto.toFixUi(): LocateFixUi? {
    val recorded = recordedAt ?: return null
    return LocateFixUi(
        deviceId = deviceId,
        lat = lat ?: return null,
        lon = lon ?: return null,
        accuracyM = accuracyM ?: 0.0,
        recordedAt = recorded,
        batteryPct = batteryPct ?: 0,
    )
}
