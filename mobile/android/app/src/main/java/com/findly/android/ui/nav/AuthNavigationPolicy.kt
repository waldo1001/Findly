package com.findly.android.ui.nav

import com.findly.android.auth.AuthState

/**
 * What [FindlyNavHost] must do to the back stack when [AuthState] changes (specs/010 §1.1 as
 * amended by row A53; specs/003 §7). There is deliberately **no pop action**: leaving Sign-in is
 * always a root replacement.
 */
sealed interface AuthNavigationAction {
    data object None : AuthNavigationAction

    /** Reset the whole stack to exactly `[Sign-in]` — a signed-out caller has nothing worth going
     * back to. */
    data object ResetToSignIn : AuthNavigationAction

    /** Reset the whole stack to exactly `[Map]`, the NavHost root; `LaunchGateViewModel` (which
     * collects the same `authState`) then decides Ready vs Onboarding for the newly signed-in user
     * (010 §1.1's table). */
    data object ResetToMap : AuthNavigationAction
}

/**
 * Pure "current route + auth state -> back-stack action" decision (specs/010 §1.1 as amended by
 * row A53; specs/003 §7, §16), extracted from `FindlyNavHost`'s `LaunchedEffect(authState)` so it
 * is unit-testable without Compose (there is no Compose UI test harness, 003 §4/§14).
 *
 * **Why sign-in success resets instead of popping (A53).** Every move *into* Sign-in is
 * [AuthNavigationAction.ResetToSignIn], which pops the whole graph inclusive and leaves Sign-in as
 * the only back-stack entry. The effect used to react to sign-in success with `popBackStack()` —
 * with nothing beneath Sign-in that is a silent no-op, so a fresh install's user stayed on
 * "Signing in…" forever (Firebase signed in and the backend registered the device; only the
 * navigation was dead; a force-stop + relaunch landed on the map). Observed 2026-10-05, Play
 * build 230. Resetting to the Map root works from any stack shape.
 *
 * - Signed in while on Sign-in -> [AuthNavigationAction.ResetToMap].
 * - Signed out anywhere but Sign-in -> [AuthNavigationAction.ResetToSignIn] (A8's account
 *   deletion, the 010 §1.1 confirmed-auth-failure wipe, a plain sign-out, and a cold start that
 *   finds no session — the `currentRoute` guard keeps it from re-resetting once already there).
 * - Everything else — including the transient [AuthState.Loading] a cold start begins with, and a
 *   signed-in caller anywhere but Sign-in — -> [AuthNavigationAction.None].
 *
 * [currentRoute] is `NavController.currentDestination?.route`: the route *template* (e.g.
 * `onboarding/{variant}`), or `null` before the graph is attached.
 */
object AuthNavigationPolicy {
    fun decide(currentRoute: String?, authState: AuthState): AuthNavigationAction {
        val onSignIn = currentRoute == Destinations.SignIn.route
        return when (authState) {
            is AuthState.SignedIn -> if (onSignIn) AuthNavigationAction.ResetToMap else AuthNavigationAction.None
            is AuthState.SignedOut -> if (onSignIn) AuthNavigationAction.None else AuthNavigationAction.ResetToSignIn
            is AuthState.Loading -> AuthNavigationAction.None
        }
    }
}
