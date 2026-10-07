package com.findly.android.pendinglink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** specs/010 §1.3 end to end over the pure pieces: capture stores with `receivedAt = now`; replay
 * clears the slot FIRST, then hands the link out exactly once; expiry discards silently. */
class PendingLinkCoordinatorTest {

    private val canAct = LinkAppState(signedIn = true, launchResolved = true, locked = false)
    private val signedOut = LinkAppState(signedIn = false, launchResolved = false, locked = false)
    private val hour = 60L * 60 * 1000

    private val store = PendingLinkStore(InMemoryPendingLinkPersistence())
    private val coordinator = PendingLinkCoordinator(store)
    private val family = IncomingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ")

    @Test
    fun `a link arriving while signed out is stored with receivedAt = now and does not navigate`() {
        val decision = coordinator.onIncoming(family, signedOut, now = 500L)

        assertEquals(CaptureDecision.Store(family), decision)
        assertEquals(PendingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ", 500L), store.current.value)
    }

    @Test
    fun `a link arriving while the app can act navigates now and stores nothing`() {
        val decision = coordinator.onIncoming(family, canAct, now = 500L)

        assertEquals(CaptureDecision.NavigateNow(family), decision)
        assertNull(store.current.value)
    }

    @Test
    fun `an unparseable link is not stored`() {
        assertEquals(CaptureDecision.Ignore, coordinator.onIncoming(null, signedOut, now = 1L))
        assertEquals(
            CaptureDecision.Ignore,
            coordinator.onIncoming(IncomingLink(PendingLinkKind.GroupJoin, null), signedOut, now = 1L),
        )
        assertNull(store.current.value)
    }

    @Test
    fun `a newer link replaces an older one`() {
        coordinator.onIncoming(family, signedOut, now = 1L)
        val group = IncomingLink(PendingLinkKind.GroupJoin, "AB12CD34")
        coordinator.onIncoming(group, signedOut, now = 2L)

        assertEquals(PendingLink(PendingLinkKind.GroupJoin, "AB12CD34", 2L), store.current.value)
    }

    @Test
    fun `replay clears the slot before navigating, and happens exactly once`() {
        coordinator.onIncoming(family, signedOut, now = 0L)
        val seenInsideNavigate = mutableListOf<PendingLink?>()
        val navigated = mutableListOf<PendingLink>()

        val first = coordinator.replayIfReady(canAct, now = 10L) { link ->
            seenInsideNavigate += store.current.value
            navigated += link
        }
        val second = coordinator.replayIfReady(canAct, now = 11L) { navigated += it }

        assertEquals(true, first)
        assertEquals(false, second)
        assertEquals(listOf<PendingLink?>(null), seenInsideNavigate)
        assertEquals(listOf(PendingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ", 0L)), navigated)
    }

    @Test
    fun `replay waits (keeps the slot) while the app cannot act yet`() {
        coordinator.onIncoming(family, signedOut, now = 0L)
        var called = false

        val replayed = coordinator.replayIfReady(signedOut, now = 10L) { called = true }

        assertEquals(false, replayed)
        assertEquals(false, called)
        assertEquals(PendingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ", 0L), store.current.value)
    }

    @Test
    fun `an expired link is discarded silently on read and never replayed`() {
        coordinator.onIncoming(family, signedOut, now = 0L)
        var called = false

        val replayed = coordinator.replayIfReady(canAct, now = hour) { called = true }

        assertEquals(false, replayed)
        assertEquals(false, called)
        assertNull(store.current.value)
    }

    @Test
    fun `replay survives simulated process death between capture and sign-in`() {
        val persistence = InMemoryPendingLinkPersistence()
        PendingLinkCoordinator(PendingLinkStore(persistence)).onIncoming(family, signedOut, now = 0L)

        val reborn = PendingLinkCoordinator(PendingLinkStore(persistence))
        val navigated = mutableListOf<PendingLink>()
        reborn.replayIfReady(canAct, now = 5L) { navigated += it }

        assertEquals(listOf(PendingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ", 0L)), navigated)
    }

    @Test
    fun `a link arriving while locked is stored, waits through the lock, and replays once after unlock (010 1_4)`() {
        val locked = LinkAppState(signedIn = true, launchResolved = true, locked = true)

        assertEquals(CaptureDecision.Store(family), coordinator.onIncoming(family, locked, now = 0L))
        assertEquals(false, coordinator.replayIfReady(locked, now = 10L) { error("must not replay while locked") })

        val replayed = mutableListOf<PendingLink>()
        assertEquals(true, coordinator.replayIfReady(canAct, now = 20L) { replayed += it })
        assertEquals(1, replayed.size)
        assertNull(store.current.value)
    }
}
