package com.findly.android.ui.nav

import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * Route string constants (specs/003-android-client.md §12; §12's amendment, specs/010-app-shell-
 * and-screen-ux.md §6: `Home` is deleted — the NavHost start destination is now [Map]). [Map]/
 * [History]/[Geofences]/[Locate] were reserved in A1 and are wired to real screens in A2;
 * The A2-added combined `Invites` destination (§3.3/§3.4) was split by A36 into [InviteCreate]/
 * [InviteAccept] (specs/010-app-shell-and-screen-ux.md §5.1/§5.2/§6) — see their own docs below.
 * A5
 * additively adds the groups destinations below (specs/005-temporary-groups.md). [Onboarding] is
 * the 010 §2.2 addition replacing the retired `Home`/`GroupsListScreen.ProfileNeeded` first-run UI.
 * A35 (specs/010 §4.1) retires the old `Settings` constant in favor of [Devices]/[Family]/
 * [Privacy] — the same three-route split iOS already had.
 *
 * [Locate] carries no path argument: the target member is passed via [FindlyNavHost]'s own
 * `remember`-held selection state (set by [com.findly.android.ui.map.MapScreen]'s
 * `onSelectMember`) rather than a nav-graph path segment, deliberately — at the time A2 wrote
 * this, the app had no external deep-link entry points, so there was nothing to gain from a
 * `{userId}` path template (and everything to lose from hand-rolling percent-encoding for a
 * `displayName` that may contain spaces, without a toolchain here to compile-verify it). A5 adds
 * this app's first external deep link ([GroupJoin]'s `findly://group-join`), but its payload (an
 * 8-char Crockford-base32 code, 001 §1.4) has no such encoding risk — see [GroupDetail]'s doc for
 * why a real `{groupId}` path argument is fine there too. [Onboarding]'s `variant` **is** a real
 * path argument for the same reason: [OnboardingVariant]'s two wire values are a closed,
 * hand-written enum with no reserved-character risk, unlike a free-form `displayName`.
 */
sealed class Destinations(val route: String) {
    data object Map : Destinations("map")
    data object History : Destinations("history")
    data object Geofences : Destinations("geofences")
    data object Locate : Destinations("locate")

    /** specs/010-app-shell-and-screen-ux.md §4.1: the monolithic `Settings` destination is
     * retired (`ui/settings/SettingsScreen.kt` is deleted) in favor of the three routes below —
     * the same decomposition iOS already had (`DeviceSettingsScreen`/`FamilyMembersScreen`/its
     * privacy screen). [Devices]/[Family] are new; [Privacy] replaces `Settings` at the same
     * `PrivacyStateHolder`/`PrivacyUiState`/`PrivacyViewModel` (unchanged — only where they
     * render moved, see `PrivacyScreen.kt`'s doc). */
    data object Devices : Destinations("devices")
    data object Family : Destinations("family")
    data object Privacy : Destinations("privacy")

    /** specs/010-app-shell-and-screen-ux.md §5.1/§6: the combined `Invites` destination splits
     * into this (parent-only, drawer) and [InviteAccept] (onboarding/deep link) — mirroring
     * iOS's two routes, which never had a combined screen to split. */
    data object InviteCreate : Destinations("invite-create")

    /** specs/010-app-shell-and-screen-ux.md §5.2. `?code={code}` is an optional query argument,
     * matched both by plain in-app navigation (no code) and by the `findly://family-join?code=…`
     * deep link declared on this same composable in [com.findly.android.ui.nav.FindlyNavHost] —
     * the same "remembered nav-graph query argument" shape as [GroupJoin] below, for the same
     * reason (an 8-char Crockford-base32 code has no percent-encoding risk). The incoming `code`
     * is untrusted and MUST be sanitized via
     * [com.findly.android.ui.invites.FamilyInviteCodeSanitizer] before use. The
     * `https://{JOIN_LINK_HOST}/f#{CODE}` form is matched separately by
     * [com.findly.android.MainActivity] (007 §1: the code lives in the URL fragment, which this
     * query-argument deep-link syntax cannot express) — see [GroupJoin]'s doc for why. */
    data object InviteAccept : Destinations("invite-accept") {
        const val ARG_CODE = "code"
        const val ROUTE_WITH_ARG = "invite-accept?code={code}"
        const val DEEP_LINK_URI_PATTERN = "findly://family-join?code={code}"
    }

    data object SignIn : Destinations("sign-in")

    /** specs/010-app-shell-and-screen-ux.md §2.2 — one route, two variants (both retiring
     * `GroupsListScreen.ProfileNeeded` and, on iOS, `Home`'s `profileless`/`familyless` branches).
     * Always reached via a full stack reset (010 §2.1/§2.2: "no back affordance, no drawer") —
     * either the 010 §1.1 launch gate or the 010 §2.1 dead-end routing rule. */
    data object Onboarding : Destinations("onboarding/{variant}") {
        const val ARG_VARIANT = "variant"
        const val ROUTE_WITH_ARG = "onboarding/{variant}"

        private fun OnboardingVariant.wireValue(): String = when (this) {
            OnboardingVariant.ProfileLess -> "profileLess"
            OnboardingVariant.FamilyLess -> "familyLess"
        }

        fun createRoute(variant: OnboardingVariant) = "onboarding/${variant.wireValue()}"

        /** Parses the path argument back into an [OnboardingVariant] — defaults to [OnboardingVariant.ProfileLess]
         * (the strictly more restrictive variant: no display name pre-supposed, no `Groups`
         * shortcut assumed) on any unrecognized/missing value, so a malformed route can never
         * strand the caller with a crash or a blank screen. */
        fun parseVariant(raw: String?): OnboardingVariant = when (raw) {
            "familyLess" -> OnboardingVariant.FamilyLess
            else -> OnboardingVariant.ProfileLess
        }
    }

    /** A21 (001 §3.1, specs/003 §12.2's `ProfileNeeded` first-run flow): the client's only
     * `POST /families` entry point — see [com.findly.android.ui.family.CreateFamilyStateHolder]'s
     * doc for why this destination didn't exist before. Reached from
     * [com.findly.android.ui.groups.GroupsListScreen]'s profile-less branch, same
     * remembered-prefill pattern as [GroupCreate]/[GroupJoin] below (this class's own doc). */
    data object CreateFamily : Destinations("family-create")

    // --- A5 additions (specs/005-temporary-groups.md; specs/003-android-client.md §12.2) ---

    /** The groups list — also the family-less home (§1.5.4); reachable from [Home] like every
     * destination above. */
    data object Groups : Destinations("groups")

    data object GroupCreate : Destinations("group-create")

    /** `{groupId}` is a real nav-graph path argument, unlike [Locate]'s remembered-selection
     * approach — a `grp_` + 20 `[A-Za-z0-9]` id (001 §1.4) has no spaces/reserved characters to
     * percent-encode, so this destination doesn't have the risk [Locate]'s doc calls out. */
    data object GroupDetail : Destinations("group-detail/{groupId}") {
        fun createRoute(groupId: String) = "group-detail/$groupId"
    }

    data object GroupMap : Destinations("group-map/{groupId}") {
        fun createRoute(groupId: String) = "group-map/$groupId"
    }

    /** Base route has no code; `?code={code}` is an optional query argument matched both by plain
     * in-app navigation (no code) and by the `findly://group-join?code=…` deep link declared on
     * this same composable in [com.findly.android.ui.nav.FindlyNavHost] — the app's first and
     * only external deep link (005 §5, "HTTPS universal join links... deferred"). The incoming
     * `code` is untrusted and MUST be sanitized via
     * [com.findly.android.ui.groups.GroupJoinCodeSanitizer] before use, never trusted as-is. */
    data object GroupJoin : Destinations("group-join") {
        const val ARG_CODE = "code"
        const val ROUTE_WITH_ARG = "group-join?code={code}"
        const val DEEP_LINK_URI_PATTERN = "findly://group-join?code={code}"
    }
}
