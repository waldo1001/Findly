package com.findly.android.location

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * specs/009-device-runtime.md §7, specs/003-android-client.md §11 — the permission flow's decision
 * logic, kept pure so the disclosure gate and the degraded-state banner are testable without an
 * emulator or Compose.
 *
 * Deliberately mirrors iOS's `PermissionFlowPolicy` case for case: §7 is cross-platform normative,
 * and the two clients answering "should we show the disclosure now?" differently is exactly the
 * drift the shared spec exists to prevent.
 *
 * Exists because §7 was normative from A2 onward and never implemented — `MainActivity` carries the
 * admission as a TODO ("a prominent disclosure before this OS prompt, and a persistent denial
 * banner, are both still missing for every permission in this codebase"). It is a Play policy
 * requirement for background location, and review wants a video of the flow.
 */
class PermissionFlowPolicyTest {

    // --- The disclosure gate (009 §7: disclosure BEFORE the OS prompt) ---

    @Test
    fun `undisclosed and undetermined shows disclosure before any OS prompt`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = false,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.ShowDisclosure(PermissionDisclosureKind.FOREGROUND), step)
    }

    @Test
    fun `after foreground disclosure requests foreground permission`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = true,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.RequestForeground, step)
    }

    @Test
    fun `background upgrade is gated behind its own disclosure`() {
        // 003 §11.2: Android 11+ forbids bundling foreground and background in one dialog, so the
        // background ask is a separate, later request preceded by its own rationale.
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.WHEN_IN_USE,
            foregroundDisclosureAcknowledged = true,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = true,
        )

        assertEquals(PermissionFlowStep.ShowDisclosure(PermissionDisclosureKind.BACKGROUND), step)
    }

    @Test
    fun `after background disclosure requests the upgrade`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.WHEN_IN_USE,
            foregroundDisclosureAcknowledged = true,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = true,
            backgroundDisclosureDeclined = false,
            requiresBackground = true,
        )

        assertEquals(PermissionFlowStep.RequestBackgroundUpgrade, step)
    }

    @Test
    fun `when in use is enough when the interval does not need background`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.WHEN_IN_USE,
            foregroundDisclosureAcknowledged = true,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.None, step)
    }

    @Test
    fun `fully authorized asks for nothing`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.ALWAYS,
            foregroundDisclosureAcknowledged = true,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = true,
            backgroundDisclosureDeclined = false,
            requiresBackground = true,
        )

        assertEquals(PermissionFlowStep.None, step)
    }

    @Test
    fun `denied never re-prompts and never re-shows disclosure`() {
        // Android stops showing the dialog after the user has refused; re-asking is nagging that
        // cannot succeed. 003 §11.5 routes to system settings via the banner instead.
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.DENIED,
            foregroundDisclosureAcknowledged = false,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = true,
        )

        assertEquals(PermissionFlowStep.None, step)
    }

    // --- A25 (009 §7): "Not now" is answered too — the disclosure MUST NOT auto-re-present once
    // declined, on this or any later launch. ---

    @Test
    fun `a declined foreground disclosure does not auto-re-present`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = false,
            foregroundDisclosureDeclined = true,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.None, step)
    }

    @Test
    fun `a declined foreground disclosure also does not fire the OS prompt`() {
        // Declining the in-app explanation must not be silently promoted into consent to ask the
        // OS — that would invert 009 §7's "disclosure precedes the OS prompt" ordering.
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.NOT_DETERMINED,
            foregroundDisclosureAcknowledged = false,
            foregroundDisclosureDeclined = true,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = false,
            requiresBackground = false,
        )

        assertEquals(PermissionFlowStep.None, step)
        assertNotEquals(PermissionFlowStep.RequestForeground, step)
    }

    @Test
    fun `a declined background disclosure does not auto-re-present`() {
        val step = PermissionFlowPolicy.nextStep(
            authorization = LocationAuthorization.WHEN_IN_USE,
            foregroundDisclosureAcknowledged = true,
            foregroundDisclosureDeclined = false,
            backgroundDisclosureAcknowledged = false,
            backgroundDisclosureDeclined = true,
            requiresBackground = true,
        )

        assertEquals(PermissionFlowStep.None, step)
    }

    // --- The degraded-state banner (009 §7: persistent, dismissible-per-session) ---

    @Test
    fun `denied foreground shows cannot-report banner`() {
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.DENIED,
            requiresBackground = false,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.CANNOT_REPORT, banner)
    }

    @Test
    fun `when in use but background needed shows foreground-only banner`() {
        // 003 §11.5: background denied falls back to foreground-only reporting WITH a banner —
        // otherwise the device silently stops reporting the moment the app is backgrounded.
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.WHEN_IN_USE,
            requiresBackground = true,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.FOREGROUND_ONLY, banner)
    }

    @Test
    fun `when in use and background not needed shows no banner`() {
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.WHEN_IN_USE,
            requiresBackground = false,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.NONE, banner)
    }

    @Test
    fun `fully authorized shows no banner`() {
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.ALWAYS,
            requiresBackground = true,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.NONE, banner)
    }

    @Test
    fun `dismissing suppresses the banner for this session only`() {
        // "dismissible-per-session" (009 §7): dismissal is deliberately NOT persisted, so a device
        // that cannot report is re-surfaced next launch rather than staying silently broken.
        val dismissed = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.DENIED,
            requiresBackground = false,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = true,
        )
        val freshSession = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.DENIED,
            requiresBackground = false,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.NONE, dismissed)
        assertEquals(PermissionBanner.CANNOT_REPORT, freshSession)
    }

    @Test
    fun `cannot-report outranks foreground-only`() {
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.DENIED,
            requiresBackground = true,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.CANNOT_REPORT, banner)
    }

    // --- A25 (009 §7): once the full-screen disclosure stops auto-re-presenting, the banner is the
    // only thing left telling a never-actually-asked user that this device cannot report. ---

    @Test
    fun `a declined foreground disclosure shows the cannot-report banner too`() {
        // Without this, declining once would go from "re-nagged every launch" straight to
        // "silently invisible forever" — neither is 009 §7's persistent, honest degraded state.
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.NOT_DETERMINED,
            requiresBackground = false,
            foregroundDisclosureDeclined = true,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.CANNOT_REPORT, banner)
    }

    @Test
    fun `an undecided undetermined state still shows no banner`() {
        // The disclosure/prompt flow is what should be running instead — not yet declined, not yet
        // answered.
        val banner = PermissionFlowPolicy.banner(
            authorization = LocationAuthorization.NOT_DETERMINED,
            requiresBackground = false,
            foregroundDisclosureDeclined = false,
            dismissedThisSession = false,
        )

        assertEquals(PermissionBanner.NONE, banner)
    }

    // --- A25 (009 §7): the banner's action button re-opens the full-screen disclosure, except when
    // the OS itself has already irrevocably refused — there, only system settings can help. ---

    @Test
    fun `an OS-level denial routes the banner action to system settings, not the disclosure`() {
        assertEquals(null, PermissionFlowPolicy.bannerReopenKind(LocationAuthorization.DENIED))
    }

    @Test
    fun `a never-asked foreground state reopens the foreground disclosure`() {
        assertEquals(
            PermissionDisclosureKind.FOREGROUND,
            PermissionFlowPolicy.bannerReopenKind(LocationAuthorization.NOT_DETERMINED),
        )
    }

    @Test
    fun `a when-in-use state reopens the background disclosure`() {
        assertEquals(
            PermissionDisclosureKind.BACKGROUND,
            PermissionFlowPolicy.bannerReopenKind(LocationAuthorization.WHEN_IN_USE),
        )
    }

    @Test
    fun `fully authorized has no reopen action (no banner is shown anyway)`() {
        assertEquals(null, PermissionFlowPolicy.bannerReopenKind(LocationAuthorization.ALWAYS))
    }
}
