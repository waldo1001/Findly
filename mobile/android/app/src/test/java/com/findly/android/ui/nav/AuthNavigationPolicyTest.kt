package com.findly.android.ui.nav

import com.findly.android.auth.AuthState
import com.findly.android.ui.onboarding.OnboardingVariant
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/**
 * [AuthNavigationPolicy] is the pure "current route + auth state -> back-stack action" decision
 * `FindlyNavHost`'s `LaunchedEffect(authState)` used to make inline (specs/010 §1.1 as amended by
 * row A53; specs/003 §7, §16) — extracted so it runs without Compose (there is no Compose UI test
 * harness, 003 §4/§14).
 *
 * The bug it pins: every move *into* Sign-in resets the whole stack to `[SignIn]`, so once
 * Firebase signs the user in there is nothing beneath Sign-in to pop back to. The old effect called
 * `popBackStack()` anyway — a silent no-op — and the screen stayed on "Signing in…" forever
 * (observed 2026-10-05, Play build 230, a fresh install).
 */
class AuthNavigationPolicyTest {

    private val signIn = Destinations.SignIn.route
    private val map = Destinations.Map.route

    /** Every route a signed-in/out caller can plausibly be on other than Sign-in itself — including
     * a null route (the graph not attached yet) and the Onboarding template route that
     * `NavDestination.route` reports (the `{variant}` placeholder, not a concrete value). */
    private val nonSignInRoutes: List<String?> = listOf(
        null,
        map,
        Destinations.Onboarding.ROUTE_WITH_ARG,
        Destinations.Onboarding.createRoute(OnboardingVariant.ProfileLess),
        Destinations.History.route,
        Destinations.Privacy.route,
        Destinations.InviteAccept.ROUTE_WITH_ARG,
        Destinations.GroupJoin.ROUTE_WITH_ARG,
    )

    @Test
    fun `sign-in success while on Sign-in resets to the Map root - it never pops`() {
        val action = AuthNavigationPolicy.decide(currentRoute = signIn, authState = AuthState.SignedIn("uid-1"))

        assertEquals(AuthNavigationAction.ResetToMap, action)
    }

    @Test
    fun `signed-out away from Sign-in resets to Sign-in`() {
        for (route in nonSignInRoutes) {
            assertEquals(
                "SignedOut on $route",
                AuthNavigationAction.ResetToSignIn,
                AuthNavigationPolicy.decide(route, AuthState.SignedOut),
            )
        }
    }

    @Test
    fun `signed-out while already on Sign-in does nothing`() {
        assertEquals(AuthNavigationAction.None, AuthNavigationPolicy.decide(signIn, AuthState.SignedOut))
    }

    @Test
    fun `signed-in anywhere other than Sign-in does nothing`() {
        for (route in nonSignInRoutes) {
            assertEquals(
                "SignedIn on $route",
                AuthNavigationAction.None,
                AuthNavigationPolicy.decide(route, AuthState.SignedIn("uid-1")),
            )
        }
    }

    @Test
    fun `the transient Loading auth state never navigates, wherever the caller is`() {
        for (route in nonSignInRoutes + signIn) {
            assertEquals(
                "Loading on $route",
                AuthNavigationAction.None,
                AuthNavigationPolicy.decide(route, AuthState.Loading),
            )
        }
    }

    /**
     * The A53 regression, end to end over a modelled back stack: a signed-out start resets the
     * stack to `[SignIn]`; sign-in success must then land on `[Map]`. A pop on that one-entry stack
     * would leave `[SignIn]` (nothing to pop to) — i.e. exactly the stuck "Signing in…" screen.
     */
    @Test
    fun `signed-out reset then sign-in success ends on the Map root, not on Sign-in`() {
        var stack: List<String> = listOf(map) // cold start: the NavHost's start destination
        fun step(authState: AuthState) {
            val action = AuthNavigationPolicy.decide(stack.lastOrNull(), authState)
            stack = when (action) {
                AuthNavigationAction.None -> stack
                AuthNavigationAction.ResetToSignIn -> listOf(signIn)
                AuthNavigationAction.ResetToMap -> listOf(map)
                else -> {
                    fail("unexpected action $action - leaving Sign-in must be a root reset, never a pop")
                    stack
                }
            }
        }

        step(AuthState.Loading)
        assertEquals(listOf(map), stack)

        step(AuthState.SignedOut)
        assertEquals("a signed-out caller is reset to Sign-in alone", listOf(signIn), stack)

        step(AuthState.SignedIn("uid-1"))
        assertEquals("sign-in success must replace Sign-in with the Map root", listOf(map), stack)

        step(AuthState.SignedIn("uid-1")) // a repeated emission must be idempotent
        assertEquals(listOf(map), stack)
    }

    @Test
    fun `an in-session sign-out then a fresh sign-in also ends on the Map root`() {
        // Account deletion / the 010 §1.1 confirmed-auth-failure wipe / a plain sign-out: the user
        // is anywhere in the app (here: a pushed Privacy screen over the map), signs out, and a
        // different (or the same) user signs in again from the Sign-in screen.
        var stack: List<String> = listOf(map, Destinations.Privacy.route)
        fun step(authState: AuthState) {
            stack = when (val action = AuthNavigationPolicy.decide(stack.lastOrNull(), authState)) {
                AuthNavigationAction.None -> stack
                AuthNavigationAction.ResetToSignIn -> listOf(signIn)
                AuthNavigationAction.ResetToMap -> listOf(map)
                else -> {
                    fail("unexpected action $action")
                    stack
                }
            }
        }

        step(AuthState.SignedOut)
        assertEquals(listOf(signIn), stack)
        step(AuthState.SignedIn("uid-2"))
        assertEquals(listOf(map), stack)
    }
}
