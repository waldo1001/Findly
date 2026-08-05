package com.findly.android.location

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * specs/009-device-runtime.md §7 — collapsing Android's two independent permission booleans onto
 * the four states [PermissionFlowPolicy] reasons about.
 *
 * **The hard part is telling "never asked" from "refused."** Android exposes no API for it:
 * `checkSelfPermission` returns DENIED in both cases, and `shouldShowRequestPermissionRationale`
 * is famously ambiguous (false both before the first ask and after a permanent denial). The
 * distinction matters because only one of the two can still be prompted — the other must go
 * straight to the banner's system-settings route (003 §11.5).
 *
 * This resolves it from state the app already keeps: the **disclosure acknowledgement**. The app
 * only ever prompts after the disclosure is acknowledged, so "acknowledged but still not granted"
 * can only mean the user saw the OS dialog and refused. No extra persisted flag, and nothing that
 * can drift out of sync with the thing that actually gates the prompt.
 */
class LocationAuthorizationResolverTest {

    @Test
    fun `nothing granted and nothing acknowledged means never asked`() {
        val auth = LocationAuthorizationResolver.resolve(
            fineGranted = false,
            backgroundGranted = false,
            foregroundDisclosureAcknowledged = false,
        )

        assertEquals(LocationAuthorization.NOT_DETERMINED, auth)
    }

    @Test
    fun `acknowledged but still not granted means refused`() {
        // The app never prompts before acknowledgement, so this state can only be reached by the
        // user seeing the OS dialog and saying no.
        val auth = LocationAuthorizationResolver.resolve(
            fineGranted = false,
            backgroundGranted = false,
            foregroundDisclosureAcknowledged = true,
        )

        assertEquals(LocationAuthorization.DENIED, auth)
    }

    @Test
    fun `fine only is foreground authorization`() {
        val auth = LocationAuthorizationResolver.resolve(
            fineGranted = true,
            backgroundGranted = false,
            foregroundDisclosureAcknowledged = true,
        )

        assertEquals(LocationAuthorization.WHEN_IN_USE, auth)
    }

    @Test
    fun `fine plus background is full authorization`() {
        val auth = LocationAuthorizationResolver.resolve(
            fineGranted = true,
            backgroundGranted = true,
            foregroundDisclosureAcknowledged = true,
        )

        assertEquals(LocationAuthorization.ALWAYS, auth)
    }

    @Test
    fun `background without fine is still only foreground`() {
        // Not reachable through the UI, but the OS can report it after a settings change. Treating
        // it as ALWAYS would let the app believe it can report in the background when the platform
        // will refuse every fix — fine location is the prerequisite.
        val auth = LocationAuthorizationResolver.resolve(
            fineGranted = false,
            backgroundGranted = true,
            foregroundDisclosureAcknowledged = true,
        )

        assertEquals(LocationAuthorization.DENIED, auth)
    }

    @Test
    fun `granting outranks acknowledgement state entirely`() {
        // A user who grants permission from system settings without ever seeing the disclosure
        // must not be reported as NOT_DETERMINED — what is actually granted is the ground truth.
        val auth = LocationAuthorizationResolver.resolve(
            fineGranted = true,
            backgroundGranted = true,
            foregroundDisclosureAcknowledged = false,
        )

        assertEquals(LocationAuthorization.ALWAYS, auth)
    }
}
