package com.findly.android.pendinglink

import com.findly.android.launch.LaunchUiState
import com.findly.android.ui.nav.Destinations

/** Which screen a join/invite link opens (specs/007 section 1/4; 010 section 1.3). */
enum class PendingLinkKind { FamilyInvite, GroupJoin }

/** A link that went through the 007 parsers. [code] is the sanitized code, `null` when the link
 * matched but carried no usable code (007 section 4: join screen without prefill). */
data class IncomingLink(val kind: PendingLinkKind, val code: String?)

/** The one pending-link slot's content (010 section 1.3). The code is never logged. */
data class PendingLink(val kind: PendingLinkKind, val code: String, val receivedAt: Long) {
    override fun toString() = "PendingLink(kind=$kind, receivedAt=$receivedAt)" // no code in logs
}

/** An incoming link delivered by the Activity; [seq] makes two identical links distinct events. */
data class IncomingLinkEvent(val seq: Long, val link: IncomingLink?)

/**
 * Whether the app can act on a link right now (010 section 1.3 "Capture"): [signedIn] is false
 * while signed out or auth restore is unfinished; [launchResolved] means launch resolution
 * (section 1.1) landed on its root; [locked] is the section 1.4 lock screen (task A63 supplies it;
 * until then it is always false).
 */
data class LinkAppState(val signedIn: Boolean, val launchResolved: Boolean, val locked: Boolean = false) {
    val canAct: Boolean get() = signedIn && launchResolved && !locked
}

sealed interface CaptureDecision {
    data class NavigateNow(val link: IncomingLink) : CaptureDecision
    data class Store(val link: IncomingLink) : CaptureDecision
    data object Ignore : CaptureDecision
}

sealed interface ReplayDecision {
    data class Replay(val link: PendingLink) : ReplayDecision
    data object Discard : ReplayDecision
    data object Wait : ReplayDecision
}

/** Pure decisions of specs/010 section 1.3 (unit-tested without a UI). */
object PendingLinkPolicy {
    const val VALIDITY_MILLIS: Long = 60L * 60 * 1000

    fun capture(link: IncomingLink?, state: LinkAppState): CaptureDecision {
        if (link == null) return CaptureDecision.Ignore
        if (link.code == null) {
            // Nothing worth keeping: handled as before - join screen without prefill when signed
            // in (and not behind the lock), ignored otherwise.
            return if (state.signedIn && !state.locked) CaptureDecision.NavigateNow(link) else CaptureDecision.Ignore
        }
        return if (state.canAct) CaptureDecision.NavigateNow(link) else CaptureDecision.Store(link)
    }

    fun replay(pending: PendingLink?, now: Long, state: LinkAppState): ReplayDecision {
        if (pending == null) return ReplayDecision.Wait
        val age = now - pending.receivedAt
        // Valid for 1 hour: expired at exactly 1 h. A negative age (clock moved back) is discarded
        // rather than kept indefinitely.
        if (age < 0 || age >= VALIDITY_MILLIS) return ReplayDecision.Discard
        return if (state.canAct) ReplayDecision.Replay(pending) else ReplayDecision.Wait
    }

    /** Launch resolution (010 section 1.1) has landed on its root, and the stack is past the
     * transient frames: replaying while Onboarding is still pending but the stack sits on the Map
     * would be wiped by the imminent reset to Onboarding. */
    fun isLaunchResolved(launch: LaunchUiState, currentRoute: String?): Boolean = when (launch) {
        is LaunchUiState.Ready -> currentRoute != null && currentRoute != Destinations.SignIn.route
        is LaunchUiState.Onboarding ->
            currentRoute != null && currentRoute != Destinations.SignIn.route && currentRoute != Destinations.Map.route
        else -> false
    }
}
