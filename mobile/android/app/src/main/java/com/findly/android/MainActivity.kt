package com.findly.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.groups.GroupJoinHttpsLinkParser
import com.findly.android.ui.home.HomeViewModel
import com.findly.android.ui.home.HomeViewModelFactory
import com.findly.android.ui.nav.FindlyNavHost

/** The single Activity (Compose Navigation pattern, specs/003-android-client.md §12). Registers
 * itself with [AppContainer] as the current foreground Activity (specs/006-phone-auth.md §6,
 * specs/003 §7) — `FirebaseAuthProvider`'s phone verification needs a live `Activity` for Play
 * Integrity / reCAPTCHA app verification.
 *
 * **A6 addition** (specs/007-public-join-links.md, specs/003-android-client.md §12.3): the
 * launching `Intent`'s `data` `Uri` is checked once, here, against this app's configured
 * `https://{JOIN_LINK_HOST}/g#CODE` join-link shape via [GroupJoinHttpsLinkParser] — deliberately
 * *not* through Navigation Compose's own `navDeepLink` URI-pattern matching (used below this class
 * for the `findly://group-join?code=…` link), since that matching is path/query-argument based and
 * the join code lives in the URL **fragment** (007 §1), read directly via `Uri.getFragment()`. The
 * parsed [GroupJoinHttpsLinkParser.Result] is then handed to [FindlyNavHost] once, at composition;
 * its own `LaunchedEffect(Unit)` performs the one-time navigation, so this never re-fires on later
 * *in-app* navigation back to [com.findly.android.ui.nav.Destinations.GroupJoin] (re-checking
 * the live `Activity.intent` from inside the nav graph itself would have exactly that staleness
 * bug, since `Activity.intent` doesn't change on in-app `NavController.navigate()` calls).
 *
 * **Code-review fix (2026-07-22):** the parsing above is additionally guarded by
 * `savedInstanceState == null` — i.e. routed through [GroupJoinHttpsLinkParser.parseIfFreshLaunch]
 * rather than [GroupJoinHttpsLinkParser.parse] directly. Without this, rotation, a dark/light-mode
 * toggle, multi-window resize, a font-scale/locale change, or process-death restore all recreate
 * this Activity with a **fresh** `onCreate` (and so a fresh [FindlyNavHost] composition, and so a
 * fresh `LaunchedEffect(Unit)`) while `getIntent()` keeps handing back the exact same original
 * launch `Uri` — so a user who tapped the https link, landed on `GroupJoin`, then navigated
 * elsewhere (e.g. Settings), would get forcibly yanked back to `GroupJoin` by the next rotation.
 * `savedInstanceState` is non-null on precisely those recreations (the system only supplies it
 * when restoring previously-saved state) and null on a genuinely new launch — the standard Android
 * idiom for "handle this Intent once, not on every recreation." */
class MainActivity : ComponentActivity() {

    private val container get() = (application as FindlyApplication).container

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        container.onActivityStarted(this)

        val launchingUri = intent?.data
        val httpsJoinLinkResult = GroupJoinHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = savedInstanceState == null,
            scheme = launchingUri?.scheme,
            host = launchingUri?.host,
            path = launchingUri?.path,
            fragment = launchingUri?.fragment,
            joinLinkHost = container.appConfig.joinLinkHost,
        )

        setContent {
            FindlyTheme {
                val homeViewModel: HomeViewModel = viewModel(
                    factory = HomeViewModelFactory(container.authProvider, container.deviceRegistrar),
                )
                // Sign-in navigation lives inside FindlyNavHost itself (specs/003 §7, §12) — it
                // owns the NavController the real path needs.
                FindlyNavHost(
                    container = container,
                    homeViewModel = homeViewModel,
                    httpsJoinLinkResult = httpsJoinLinkResult,
                )
            }
        }
    }

    override fun onDestroy() {
        container.onActivityStopped(this)
        super.onDestroy()
    }
}
