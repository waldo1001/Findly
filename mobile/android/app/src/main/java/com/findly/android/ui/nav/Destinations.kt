package com.findly.android.ui.nav

/**
 * Route string constants (specs/003-android-client.md §12). [Home]/[Map]/[History]/[Geofences]/
 * [Locate]/[Settings] were reserved in A1 and are wired to real screens in A2; [Invites] is a new
 * A2 addition (§3.3/§3.4) — additive, same convention as the rest. A5 additively adds the groups
 * destinations below (specs/005-temporary-groups.md).
 *
 * [Locate] carries no path argument: the target member is passed via [FindlyNavHost]'s own
 * `remember`-held selection state (set by [com.findly.android.ui.map.MapScreen]'s
 * `onSelectMember`) rather than a nav-graph path segment, deliberately — at the time A2 wrote
 * this, the app had no external deep-link entry points, so there was nothing to gain from a
 * `{userId}` path template (and everything to lose from hand-rolling percent-encoding for a
 * `displayName` that may contain spaces, without a toolchain here to compile-verify it). A5 adds
 * this app's first external deep link ([GroupJoin]'s `findly://group-join`), but its payload (an
 * 8-char Crockford-base32 code, 001 §1.4) has no such encoding risk — see [GroupDetail]'s doc for
 * why a real `{groupId}` path argument is fine there too.
 */
sealed class Destinations(val route: String) {
    data object Home : Destinations("home")
    data object Map : Destinations("map")
    data object History : Destinations("history")
    data object Geofences : Destinations("geofences")
    data object Locate : Destinations("locate")
    data object Settings : Destinations("settings")
    data object Invites : Destinations("invites")
    data object SignIn : Destinations("sign-in")

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
