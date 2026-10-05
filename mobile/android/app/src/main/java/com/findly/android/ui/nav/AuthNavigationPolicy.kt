package com.findly.android.ui.nav

import com.findly.android.auth.AuthState

/**
 * What [FindlyNavHost] must do to the back stack when [AuthState] changes (specs/010 §1.1 as
 * amended by row A53; specs/003 §7).
 *
 * RED SKELETON (A53): [decide] below is the pre-fix decision extracted verbatim from
 * `FindlyNavHost`'s `LaunchedEffect(authState)`, so the new tests fail on exactly the shipped bug.
 */
sealed interface AuthNavigationAction {
    data object None : AuthNavigationAction
    data object ResetToSignIn : AuthNavigationAction
    data object ResetToMap : AuthNavigationAction
    data object PopBackStack : AuthNavigationAction
}

object AuthNavigationPolicy {
    fun decide(currentRoute: String?, authState: AuthState): AuthNavigationAction {
        if (authState is AuthState.SignedIn && currentRoute == Destinations.SignIn.route) {
            return AuthNavigationAction.PopBackStack
        }
        if (authState is AuthState.SignedOut && currentRoute != Destinations.SignIn.route) {
            return AuthNavigationAction.ResetToSignIn
        }
        return AuthNavigationAction.None
    }
}
