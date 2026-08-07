package com.findly.android.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/009-device-runtime.md §7 — the persisted half of the disclosure gate.
 *
 * Acknowledgement MUST survive relaunch (nobody should re-read the same explanation every launch),
 * which is deliberately the opposite of the banner's dismissal — that one is session-only, so a
 * device that cannot report is re-surfaced next launch. The two live in different places precisely
 * so one is not later "simplified" into the other.
 */
class PermissionDisclosureStoreTest {

    @Test
    fun `nothing is acknowledged initially`() {
        val store = InMemoryPermissionDisclosureStore()

        assertFalse(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `acknowledging one kind does not acknowledge the other`() {
        // 003 §11.2: the background ask is a SEPARATE, later request with its own rationale.
        // One shared flag would silently skip the background disclosure — the exact screen Play's
        // background-location review looks for.
        val store = InMemoryPermissionDisclosureStore()

        store.acknowledge(PermissionDisclosureKind.FOREGROUND)

        assertTrue(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `acknowledgement is idempotent`() {
        val store = InMemoryPermissionDisclosureStore()

        store.acknowledge(PermissionDisclosureKind.BACKGROUND)
        store.acknowledge(PermissionDisclosureKind.BACKGROUND)

        assertTrue(store.isAcknowledged(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `clear forgets everything`() {
        // Part of the account-deletion local wipe (specs/008 §4.4): a different user on this device
        // must see the disclosure again — this is consent, not a device-level preference.
        val store = InMemoryPermissionDisclosureStore()
        store.acknowledge(PermissionDisclosureKind.FOREGROUND)
        store.acknowledge(PermissionDisclosureKind.BACKGROUND)

        store.clear()

        assertFalse(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.BACKGROUND))
    }

    // --- A25 (009 §7): "Not now" is answered too, and MUST be persisted so the full-screen
    // disclosure does not auto-re-present on the next cold launch. ---

    @Test
    fun `nothing is declined initially`() {
        val store = InMemoryPermissionDisclosureStore()

        assertFalse(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `declining one kind does not decline the other`() {
        val store = InMemoryPermissionDisclosureStore()

        store.decline(PermissionDisclosureKind.FOREGROUND)

        assertTrue(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `decline is idempotent`() {
        val store = InMemoryPermissionDisclosureStore()

        store.decline(PermissionDisclosureKind.BACKGROUND)
        store.decline(PermissionDisclosureKind.BACKGROUND)

        assertTrue(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `decline survives independently of acknowledgement`() {
        // A kind is never both at once in practice, but the store must not conflate the two flags.
        val store = InMemoryPermissionDisclosureStore()

        store.decline(PermissionDisclosureKind.FOREGROUND)

        assertTrue(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
    }

    @Test
    fun `clearDeclined forgets only that kind's decline, for reopening from the banner`() {
        // A25 (009 §7): an explicit action on the banner re-opens the full-screen disclosure —
        // implemented by forgetting the prior decline so the flow gate presents it again.
        val store = InMemoryPermissionDisclosureStore()
        store.decline(PermissionDisclosureKind.FOREGROUND)
        store.decline(PermissionDisclosureKind.BACKGROUND)

        store.clearDeclined(PermissionDisclosureKind.FOREGROUND)

        assertFalse(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertTrue(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `clear forgets declines too — part of the account-deletion local wipe`() {
        val store = InMemoryPermissionDisclosureStore()
        store.decline(PermissionDisclosureKind.FOREGROUND)
        store.decline(PermissionDisclosureKind.BACKGROUND)

        store.clear()

        assertFalse(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `the flow gate does not re-present after a persisted decline`() {
        // The actual bug (A25): "Not now" used to live only in Compose `remember` state, so a
        // fresh process (cold launch) always saw an empty decline set and re-showed the disclosure.
        val store = InMemoryPermissionDisclosureStore()

        store.decline(PermissionDisclosureKind.FOREGROUND)
        val afterColdLaunch = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = store.isAcknowledged(PermissionDisclosureKind.FOREGROUND),
            foregroundDisclosureDeclined = store.isDeclined(PermissionDisclosureKind.FOREGROUND),
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.None, afterColdLaunch)
    }

    @Test
    fun `the flow gate reads through the store`() {
        // The pairing that matters: an acknowledged disclosure is what lets the policy advance from
        // "explain" to "ask the OS". Pinning it here means a storage regression surfaces as a flow
        // failure, not just a boolean one.
        val store = InMemoryPermissionDisclosureStore()

        val before = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = store.isAcknowledged(PermissionDisclosureKind.FOREGROUND),
            foregroundDisclosureDeclined = store.isDeclined(PermissionDisclosureKind.FOREGROUND),
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )
        store.acknowledge(PermissionDisclosureKind.FOREGROUND)
        val after = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = store.isAcknowledged(PermissionDisclosureKind.FOREGROUND),
            foregroundDisclosureDeclined = store.isDeclined(PermissionDisclosureKind.FOREGROUND),
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.ShowDisclosure(PermissionDisclosureKind.FOREGROUND), before)
        assertEquals(PermissionFlowStep.RequestForeground, after)
    }
}
