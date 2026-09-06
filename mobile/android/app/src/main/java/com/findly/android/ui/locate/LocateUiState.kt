package com.findly.android.ui.locate

import com.findly.android.ui.onboarding.OnboardingVariant

/** The instant "last known" answer that comes back with the create call (001-api-contract.md
 * §6.1) — `null` if the target has never reported. */
data class LastKnownUi(
    val deviceId: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val recordedAt: String,
)

/** The high-accuracy fix the target device supplies on fulfillment (§6.2/§6.3) — present only
 * once [LocateUiState.Terminal.status] is `"fulfilled"`. */
data class LocateFixUi(
    val deviceId: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val recordedAt: String,
    val batteryPct: Int,
)

/** specs/009-device-runtime.md §5.1 "Requester side": the three ways a locate request can end,
 * from the requester's point of view — `lastKnown → updating → (fresh | late | unreachable)`.
 * [FRESH] is a fulfil that landed before `expiresAt`; [LATE] is either a fulfil inside B26's
 * 10-minute post-`expiresAt` grace (`late: true` on the wire, 001 §6.2/§6.3) or one discovered by
 * [LocateStateHolder]'s one-shot `GET /locations/latest` fallback after polling stopped; [LATE] is
 * rendered exactly like [FRESH] plus an age caption (the spec's own wording). [UNREACHABLE] is
 * everything else that reaches a terminal/timeout point with no fresher position found. */
enum class LocateOutcome { FRESH, LATE, UNREACHABLE }

/** State surfaced by [LocateStateHolder] (specs/003-android-client.md §12's reserved `Locate`
 * destination, filled in by A2). [status] is the raw wire status (`"fulfilled"`, `"expired"`,
 * `"pushFailed"`) kept for precise copy (e.g. distinguishing "couldn't reach the device" from
 * "request expired"); [outcome] is the spec's three-state rendering signal. [Polling] covers
 * `"pending"`. */
sealed class LocateUiState {
    data object Idle : LocateUiState()
    data class Error(val message: String) : LocateUiState()

    data class Polling(
        val requestId: String,
        val lastKnown: LastKnownUi?,
        val expiresAt: String,
    ) : LocateUiState()

    data class Terminal(
        val requestId: String,
        val status: String,
        val outcome: LocateOutcome,
        val fix: LocateFixUi?,
        val lastKnown: LastKnownUi?,
    ) : LocateUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND`
     * on the create/poll call (Locate has no separate eager load — this *is* its load path)
     * routes to Onboarding instead of the dead-end retryable [Error] card. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : LocateUiState()
}
