package com.findly.android.pendinglink

import com.findly.android.launch.LaunchUiState
import com.findly.android.ui.nav.Destinations
import com.findly.android.ui.onboarding.OnboardingVariant
import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/010 §1.3 — the pure capture decision (link, app state -> navigate now / store) and
 * replay decision (pending link, now, app state -> replay / discard / wait); §10 "Pending link". */
class PendingLinkPolicyTest {

    private val canAct = LinkAppState(signedIn = true, launchResolved = true, locked = false)
    private val signedOut = LinkAppState(signedIn = false, launchResolved = false, locked = false)
    private val resolving = LinkAppState(signedIn = true, launchResolved = false, locked = false)
    private val locked = LinkAppState(signedIn = true, launchResolved = true, locked = true)

    private val family = IncomingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ")
    private val group = IncomingLink(PendingLinkKind.GroupJoin, "7F3K9QRZ")

    @Test
    fun `canAct requires signed in, launch resolved and not locked`() {
        assertEquals(true, canAct.canAct)
        assertEquals(false, signedOut.canAct)
        assertEquals(false, resolving.canAct)
        assertEquals(false, locked.canAct)
    }

    @Test
    fun `a parsed link while the app can act navigates now and is not stored`() {
        assertEquals(CaptureDecision.NavigateNow(family), PendingLinkPolicy.capture(family, canAct))
        assertEquals(CaptureDecision.NavigateNow(group), PendingLinkPolicy.capture(group, canAct))
    }

    @Test
    fun `a parsed link while signed out, restoring, resolving or locked is stored, never navigated`() {
        for (state in listOf(signedOut, resolving, locked)) {
            assertEquals(CaptureDecision.Store(family), PendingLinkPolicy.capture(family, state))
            assertEquals(CaptureDecision.Store(group), PendingLinkPolicy.capture(group, state))
        }
    }

    @Test
    fun `a link that parsed to no code is handled as before - join screen without prefill when signed in, ignored when signed out`() {
        val noCode = IncomingLink(PendingLinkKind.GroupJoin, null)
        assertEquals(CaptureDecision.NavigateNow(noCode), PendingLinkPolicy.capture(noCode, canAct))
        assertEquals(CaptureDecision.NavigateNow(noCode), PendingLinkPolicy.capture(noCode, resolving))
        assertEquals(CaptureDecision.Ignore, PendingLinkPolicy.capture(noCode, signedOut))
        assertEquals(CaptureDecision.Ignore, PendingLinkPolicy.capture(noCode, locked))
    }

    @Test
    fun `no link is ignored`() {
        assertEquals(CaptureDecision.Ignore, PendingLinkPolicy.capture(null, canAct))
    }

    private val t0 = 1_000_000L
    private val hour = 60L * 60 * 1000
    private val pending = PendingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ", receivedAt = t0)

    @Test
    fun `nothing pending means wait`() {
        assertEquals(ReplayDecision.Wait, PendingLinkPolicy.replay(null, t0, canAct))
    }

    @Test
    fun `a valid pending link replays once the app can act`() {
        assertEquals(ReplayDecision.Replay(pending), PendingLinkPolicy.replay(pending, t0 + 1, canAct))
    }

    @Test
    fun `a valid pending link waits while signed out, resolving or locked`() {
        for (state in listOf(signedOut, resolving, locked)) {
            assertEquals(ReplayDecision.Wait, PendingLinkPolicy.replay(pending, t0 + 1, state))
        }
    }

    @Test
    fun `valid until one millisecond before one hour, expired at exactly one hour`() {
        assertEquals(ReplayDecision.Replay(pending), PendingLinkPolicy.replay(pending, t0 + hour - 1, canAct))
        assertEquals(ReplayDecision.Discard, PendingLinkPolicy.replay(pending, t0 + hour, canAct))
    }

    @Test
    fun `an expired link is discarded even when the app cannot act yet`() {
        assertEquals(ReplayDecision.Discard, PendingLinkPolicy.replay(pending, t0 + hour + 1, signedOut))
    }

    @Test
    fun `a link stamped in the future (clock moved back) is discarded rather than kept forever`() {
        assertEquals(ReplayDecision.Discard, PendingLinkPolicy.replay(pending, t0 - 1, canAct))
    }

    private val ready = LaunchUiState.Ready("u", LaunchUiState.RegistrationStatus.Registered, null)

    @Test
    fun `ready counts as resolved on the map and on any pushed screen, never on sign-in`() {
        assertEquals(true, PendingLinkPolicy.isLaunchResolved(ready, Destinations.Map.route))
        assertEquals(true, PendingLinkPolicy.isLaunchResolved(ready, Destinations.Devices.route))
        assertEquals(false, PendingLinkPolicy.isLaunchResolved(ready, Destinations.SignIn.route))
        assertEquals(false, PendingLinkPolicy.isLaunchResolved(ready, null))
    }

    @Test
    fun `onboarding counts as resolved once the stack left the map root, so replay works from Onboarding`() {
        val onboarding = LaunchUiState.Onboarding("u", OnboardingVariant.ProfileLess)
        assertEquals(true, PendingLinkPolicy.isLaunchResolved(onboarding, Destinations.Onboarding.ROUTE_WITH_ARG))
        assertEquals(false, PendingLinkPolicy.isLaunchResolved(onboarding, Destinations.Map.route))
        assertEquals(false, PendingLinkPolicy.isLaunchResolved(onboarding, Destinations.SignIn.route))
    }

    @Test
    fun `loading and signed-out launch states are never resolved`() {
        assertEquals(false, PendingLinkPolicy.isLaunchResolved(LaunchUiState.Loading, Destinations.Map.route))
        assertEquals(false, PendingLinkPolicy.isLaunchResolved(LaunchUiState.SignedOut, Destinations.SignIn.route))
    }
}
