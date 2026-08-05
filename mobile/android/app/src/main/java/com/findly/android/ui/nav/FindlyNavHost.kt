package com.findly.android.ui.nav

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.findly.android.ui.designsystem.components.LocalNavBackAction
import androidx.navigation.navArgument
import androidx.navigation.navDeepLink
import com.findly.android.AppContainer
import com.findly.android.auth.AuthState
import com.findly.android.network.PlanLimits
import com.findly.android.ui.family.CreateFamilyRoute
import com.findly.android.ui.family.CreateFamilyViewModel
import com.findly.android.ui.family.CreateFamilyViewModelFactory
import com.findly.android.ui.geofences.GeofencesRoute
import com.findly.android.ui.geofences.GeofencesViewModel
import com.findly.android.ui.geofences.GeofencesViewModelFactory
import com.findly.android.ui.groups.CreateGroupRoute
import com.findly.android.ui.groups.CreateGroupViewModel
import com.findly.android.ui.groups.CreateGroupViewModelFactory
import com.findly.android.ui.groups.GroupDetailRoute
import com.findly.android.ui.groups.GroupDetailViewModel
import com.findly.android.ui.groups.GroupDetailViewModelFactory
import com.findly.android.ui.groups.GroupJoinCodeSanitizer
import com.findly.android.ui.groups.GroupJoinHttpsLinkParser
import com.findly.android.ui.groups.GroupJoinRoute
import com.findly.android.ui.groups.GroupJoinViewModel
import com.findly.android.ui.groups.GroupJoinViewModelFactory
import com.findly.android.ui.groups.GroupMapRoute
import com.findly.android.ui.groups.GroupMapViewModel
import com.findly.android.ui.groups.GroupMapViewModelFactory
import com.findly.android.ui.groups.GroupsListRoute
import com.findly.android.ui.groups.GroupsListUiState
import com.findly.android.ui.groups.GroupsListViewModel
import com.findly.android.ui.groups.GroupsListViewModelFactory
import com.findly.android.ui.history.HistoryRoute
import com.findly.android.ui.history.HistoryViewModel
import com.findly.android.ui.history.HistoryViewModelFactory
import com.findly.android.ui.home.HomeRoute
import com.findly.android.ui.home.HomeViewModel
import com.findly.android.ui.invites.InvitesRoute
import com.findly.android.ui.invites.InvitesViewModel
import com.findly.android.ui.invites.InvitesViewModelFactory
import com.findly.android.ui.locate.LocateRoute
import com.findly.android.ui.locate.LocateViewModel
import com.findly.android.ui.locate.LocateViewModelFactory
import com.findly.android.ui.map.MapRoute
import com.findly.android.ui.map.MapViewModel
import com.findly.android.ui.map.MapViewModelFactory
import com.findly.android.ui.settings.PrivacyViewModel
import com.findly.android.ui.settings.PrivacyViewModelFactory
import com.findly.android.ui.settings.SettingsRoute
import com.findly.android.ui.settings.SettingsViewModel
import com.findly.android.ui.settings.SettingsViewModelFactory
import com.findly.android.ui.signin.SignInRoute
import com.findly.android.ui.signin.SignInViewModel
import com.findly.android.ui.signin.SignInViewModelFactory

/**
 * Navigation scaffold (specs/003-android-client.md §12). A1 shipped only [Destinations.Home]; A2
 * wires the rest — [Destinations.Map]/[Destinations.History]/[Destinations.Geofences]/
 * [Destinations.Locate]/[Destinations.Settings]/[Destinations.Invites] — each screen's
 * `ViewModel` built from [container]'s single [com.findly.android.network.FindlyApiClient]
 * (it implements all five 001 §3–§7 port interfaces, so every factory here just narrows it to the
 * one it needs). [Destinations.SignIn] (§7) hosts the phone sign-in screen regardless of
 * `container`'s `authProvider` implementation; a [LaunchedEffect] on `authState` pops this screen
 * once sign-in succeeds, since that's when `authState` flips to `SignedIn`.
 *
 * [Destinations.Locate] takes its target from a locally-`remember`ed `pendingLocateTarget` (set
 * by tapping a roster row in [MapRoute]) rather than a nav-graph path argument — see
 * [Destinations]'s doc for why.
 *
 * Phone sign-in (specs/006-phone-auth.md): [Destinations.SignIn] is reached the same way in every
 * build variant, dev included — the former `DevAuthProvider` short-circuit (a dev sign-in button
 * bypassing the screen entirely) is removed, so the two-step phone UI is actually exercised
 * locally against `AUTH_MODE=insecure-local` (003 §7).
 *
 * **A5 additions** (specs/005-temporary-groups.md; specs/003 §12.2) — [Destinations.Groups] /
 * [Destinations.GroupCreate] / [Destinations.GroupDetail] / [Destinations.GroupMap] /
 * [Destinations.GroupJoin]: `GroupsRoute`'s create/join buttons stash the caller's `limits`/
 * `needsDisplayName` (from its own `GET /groups` load) in `pendingCreateContext` before
 * navigating — the same "remembered local state instead of a nav-graph argument" pattern
 * [Destinations]'s own doc describes for `Locate`, since [PlanLimits] and a `Boolean` aren't
 * URL-safe path segments either. [Destinations.GroupDetail]/[Destinations.GroupMap] instead use a
 * real `{groupId}` path argument (safe, no encoding risk — see [Destinations.GroupDetail]'s doc).
 * [Destinations.GroupJoin] additionally declares a [navDeepLink] for `findly://group-join?code=…`
 * — the app's first and only external deep link — whose `code` query argument is run through
 * [GroupJoinCodeSanitizer] **before** it ever reaches [GroupJoinRoute], since it is untrusted
 * external input (any app, or a malicious link, can launch this intent with an arbitrary string).
 *
 * **A6 addition** (specs/007-public-join-links.md, specs/003-android-client.md §12.3): the public
 * `https://{JOIN_LINK_HOST}/g#CODE` join link is matched *before* this composable even runs — by
 * [com.findly.android.MainActivity], which parses the launching `Intent`'s `data` `Uri` via
 * [GroupJoinHttpsLinkParser] (deliberately **not** through a second [navDeepLink] entry here, since
 * Navigation Compose's `uriPattern` placeholder matching covers path/query segments, not URL
 * fragments — and the join code lives in the fragment, 007 §1) and passes the one
 * [httpsJoinLinkResult] in. The `LaunchedEffect(Unit)` below fires that navigation exactly once per
 * *fresh composition* of [FindlyNavHost] — which is **not** the same as "once ever": rotation,
 * dark/light-mode toggle, multi-window resize, font-scale/locale change, and process-death restore
 * all recreate `MainActivity` (and so this composable) with a fresh `onCreate` while the launching
 * `Intent` stays the same. [com.findly.android.MainActivity] closes that gap on its side by
 * only ever passing a non-[GroupJoinHttpsLinkParser.Result.NoMatch] [httpsJoinLinkResult] on a
 * genuinely new launch (`savedInstanceState == null`) — see its doc for the full reasoning — so
 * this effect firing "once per fresh composition" only ever matters on that first, genuine launch.
 * This is deliberately not a re-check of the live `Activity.intent` from inside this graph itself,
 * which would re-fire on every later in-app visit to [Destinations.GroupJoin] using the same
 * (by-then-stale) intent data.
 */
@Composable
fun FindlyNavHost(
    container: AppContainer,
    homeViewModel: HomeViewModel,
    navController: NavHostController = rememberNavController(),
    httpsJoinLinkResult: GroupJoinHttpsLinkParser.Result = GroupJoinHttpsLinkParser.Result.NoMatch,
    /** A10 (specs/009-device-runtime.md §3.2): true when this composition was launched by tapping
     * the foreground-service's persistent notification — [com.findly.android.MainActivity] already
     * gates this to a fresh launch (same idiom as [httpsJoinLinkResult]'s own freshness guard, its
     * doc above), so the one-time navigation below never re-fires on rotation/recreation. */
    openSettingsOnLaunch: Boolean = false,
) {
    var pendingLocateTarget by remember { mutableStateOf<Pair<String, String>?>(null) }
    var pendingCreateContext by remember { mutableStateOf<GroupsListUiState.CreateJoinContext?>(null) }
    var pendingJoinContext by remember { mutableStateOf<GroupsListUiState.CreateJoinContext?>(null) }

    // A21 (specs/003 §12.2's ProfileNeeded first-run flow): the display name the user typed once
    // on GroupsListScreen's profile-less branch, carried to whichever of CreateFamily/Invites they
    // tap next — same "remembered local state instead of a nav-graph argument" pattern as
    // pendingLocateTarget/pendingCreateContext above (only one of these two destinations is ever
    // pending navigation at a time, so one holder suffices).
    var pendingOnboardingDisplayName by remember { mutableStateOf("") }

    val authState by container.authProvider.authState.collectAsState()
    LaunchedEffect(authState) {
        if (authState is AuthState.SignedIn && navController.currentDestination?.route == Destinations.SignIn.route) {
            navController.popBackStack()
        }
        // A8 (specs/008-privacy-endpoints.md §4.4; specs/003 §12.4): a successful account
        // deletion calls AuthProvider.signOut() after wiping local state, which flips authState
        // to SignedOut — clear the whole back stack and land on Home, which renders its own
        // sign-in prompt for a SignedOut caller (HomeScreen.kt). The `currentRoute != Home` guard
        // makes this a no-op on cold start (NavHost's own start destination is already Home by
        // the time this effect can run) and for any future explicit sign-out from Home itself.
        val currentRoute = navController.currentDestination?.route
        if (authState is AuthState.SignedOut && currentRoute != null && currentRoute != Destinations.Home.route) {
            navController.navigate(Destinations.Home.route) {
                popUpTo(Destinations.Home.route) { inclusive = true }
                launchSingleTop = true
            }
        }
    }

    // A6 (specs/007 §4, specs/003 §12.3): one-time navigation to GroupJoin when this composition
    // was launched from a matching https join link — "wrong host or path is ignored, never
    // mis-routed" is already enforced by GroupJoinHttpsLinkParser returning NoMatch, so there's
    // nothing to do here in that case (this also covers an Activity *recreation*, since
    // MainActivity only ever passes a non-NoMatch result on a genuinely fresh launch — see its
    // doc). A matching link with no usable fragment still navigates, with an empty (not error)
    // prefill, per 007 §4.
    LaunchedEffect(Unit) {
        val matched = httpsJoinLinkResult as? GroupJoinHttpsLinkParser.Result.Matched ?: return@LaunchedEffect
        val route = matched.sanitizedCode?.let { "group-join?code=$it" } ?: Destinations.GroupJoin.route
        navController.navigate(route) {
            popUpTo(Destinations.Home.route)
            launchSingleTop = true
        }
    }

    // A10 (specs/009 §3.2): one-time navigation to Settings when this composition was launched by
    // tapping the foreground-service notification — same "fire once per fresh composition" idiom
    // as the https-join-link effect above.
    LaunchedEffect(Unit) {
        if (!openSettingsOnLaunch) return@LaunchedEffect
        navController.navigate(Destinations.Settings.route) {
            popUpTo(Destinations.Home.route)
            launchSingleTop = true
        }
    }

    // specs/003 §12.5 (mirroring specs/004 §2.5 on iOS): the ONE back-affordance decision for the
    // whole graph. Every screen's FindlyTopBar reads this, so none of them decides — or forgets —
    // for itself. The system back gesture already worked; what was missing was any *visible* way
    // out, which is what users actually look for.
    //
    // `currentBackStackEntryAsState()` (not a bare `previousBackStackEntry` read) is what makes
    // this recompose as the stack changes — read outside the state stream it would be evaluated
    // once and then go stale.
    val currentBackStackEntry by navController.currentBackStackEntryAsState()
    val canGoBack = currentBackStackEntry != null && navController.previousBackStackEntry != null
    val backAction: (() -> Unit)? = if (canGoBack) {
        { navController.popBackStack() }
    } else {
        null
    }

    CompositionLocalProvider(LocalNavBackAction provides backAction) {
    NavHost(navController = navController, startDestination = Destinations.Home.route) {
        composable(Destinations.Home.route) {
            HomeRoute(
                viewModel = homeViewModel,
                onSignIn = { navController.navigate(Destinations.SignIn.route) },
                onNavigate = { route -> navController.navigate(route) },
            )
        }

        composable(Destinations.SignIn.route) {
            val signInViewModel: SignInViewModel =
                viewModel(factory = SignInViewModelFactory(container.authProvider))
            SignInRoute(viewModel = signInViewModel)
        }

        composable(Destinations.Map.route) {
            val mapViewModel: MapViewModel = viewModel(factory = MapViewModelFactory(container.findlyApiClient))
            MapRoute(
                viewModel = mapViewModel,
                mapRenderer = container.mapRenderer,
                onSelectMember = { userId, displayName ->
                    pendingLocateTarget = userId to displayName
                    navController.navigate(Destinations.Locate.route)
                },
            )
        }

        composable(Destinations.History.route) {
            val historyViewModel: HistoryViewModel = viewModel(factory = HistoryViewModelFactory(container.findlyApiClient))
            HistoryRoute(viewModel = historyViewModel)
        }

        composable(Destinations.Geofences.route) {
            val geofencesViewModel: GeofencesViewModel =
                viewModel(factory = GeofencesViewModelFactory(container.findlyApiClient))
            GeofencesRoute(viewModel = geofencesViewModel)
        }

        composable(Destinations.Locate.route) {
            val target = pendingLocateTarget
            val locateViewModel: LocateViewModel = viewModel(factory = LocateViewModelFactory(container.findlyApiClient))
            LocateRoute(
                viewModel = locateViewModel,
                targetUserId = target?.first.orEmpty(),
                targetDisplayName = target?.second ?: "family member",
            )
        }

        composable(Destinations.Settings.route) {
            val settingsViewModel: SettingsViewModel = viewModel(
                factory = SettingsViewModelFactory(container.findlyApiClient, container.findlyApiClient),
            )
            // A8 (specs/008-privacy-endpoints.md; specs/003 §12.4): a separate ViewModel/
            // StateHolder, deliberately decoupled from settingsViewModel's family/device load —
            // see SettingsScreen.kt's doc for why.
            val privacyViewModel: PrivacyViewModel = viewModel(
                factory = PrivacyViewModelFactory(
                    privacyApi = container.findlyApiClient,
                    familyApi = container.findlyApiClient,
                    authProvider = container.authProvider,
                    localStateWiper = container.localStateWiper,
                ),
            )
            SettingsRoute(viewModel = settingsViewModel, privacyViewModel = privacyViewModel)
        }

        composable(Destinations.Invites.route) {
            val invitesViewModel: InvitesViewModel = viewModel(factory = InvitesViewModelFactory(container.findlyApiClient))
            InvitesRoute(viewModel = invitesViewModel, prefillDisplayName = pendingOnboardingDisplayName)
        }

        // A21 (001 §3.1, specs/003 §12.2's ProfileNeeded flow): the client's only POST /families
        // entry point.
        composable(Destinations.CreateFamily.route) {
            val createFamilyViewModel: CreateFamilyViewModel =
                viewModel(factory = CreateFamilyViewModelFactory(container.findlyApiClient))
            CreateFamilyRoute(
                viewModel = createFamilyViewModel,
                prefillDisplayName = pendingOnboardingDisplayName,
                onCreated = { navController.popBackStack() },
            )
        }

        // --- A5: groups (specs/005-temporary-groups.md; specs/003 §12.2) ---

        composable(Destinations.Groups.route) {
            val groupsListViewModel: GroupsListViewModel =
                viewModel(factory = GroupsListViewModelFactory(container.findlyApiClient, container.findlyApiClient))
            GroupsListRoute(
                viewModel = groupsListViewModel,
                onCreateGroup = { context ->
                    pendingCreateContext = context
                    navController.navigate(Destinations.GroupCreate.route)
                },
                onJoinGroup = { context ->
                    pendingJoinContext = context
                    navController.navigate(Destinations.GroupJoin.route)
                },
                onOpenGroup = { groupId -> navController.navigate(Destinations.GroupDetail.createRoute(groupId)) },
                onManageFamily = { navController.navigate(Destinations.Invites.route) },
                // A21: the two non-group bootstrap paths off GroupsListScreen's ProfileNeeded
                // branch (001 §1.5.3) — stash the once-entered display name the same way
                // onCreateGroup/onJoinGroup stash their CreateJoinContext above.
                onCreateFamily = { displayName ->
                    pendingOnboardingDisplayName = displayName
                    navController.navigate(Destinations.CreateFamily.route)
                },
                onAcceptInvite = { displayName ->
                    pendingOnboardingDisplayName = displayName
                    navController.navigate(Destinations.Invites.route)
                },
            )
        }

        composable(Destinations.GroupCreate.route) {
            val context = pendingCreateContext
            val createGroupViewModel: CreateGroupViewModel = viewModel(
                factory = CreateGroupViewModelFactory(
                    groupsApi = container.findlyApiClient,
                    limits = context?.limits,
                    needsDisplayName = context?.needsDisplayName ?: false,
                ),
            )
            CreateGroupRoute(
                viewModel = createGroupViewModel,
                prefillDisplayName = context?.prefillDisplayName.orEmpty(),
                onCreated = { navController.popBackStack() },
            )
        }

        composable(
            route = Destinations.GroupJoin.ROUTE_WITH_ARG,
            arguments = listOf(
                navArgument(Destinations.GroupJoin.ARG_CODE) {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                },
            ),
            deepLinks = listOf(navDeepLink { uriPattern = Destinations.GroupJoin.DEEP_LINK_URI_PATTERN }),
        ) { backStackEntry ->
            val rawCode = backStackEntry.arguments?.getString(Destinations.GroupJoin.ARG_CODE)
            // The deep link's `code` is untrusted external input — sanitize before it ever
            // reaches the screen/StateHolder; an unparsable code silently prefills empty rather
            // than being trusted as-is.
            val sanitizedCode = rawCode?.let { GroupJoinCodeSanitizer.sanitize(it) }.orEmpty()
            val context = pendingJoinContext
            val groupJoinViewModel: GroupJoinViewModel = viewModel(
                factory = GroupJoinViewModelFactory(container.findlyApiClient, context?.needsDisplayName ?: false),
            )
            GroupJoinRoute(
                viewModel = groupJoinViewModel,
                prefillCode = sanitizedCode,
                prefillDisplayName = context?.prefillDisplayName.orEmpty(),
                // Not a plain popBackStack: GroupJoin is this app's only deep-link destination, so
                // a cold app start via findly://group-join can leave a back stack that never
                // contains Destinations.Groups at all — popBackStack(Groups, ...) would silently
                // no-op there, stranding the user on this (now-stale) screen. navigate() always
                // lands on Groups regardless of how this screen was reached; popUpTo(Home) plus
                // launchSingleTop avoids stacking a redundant entry on the common in-app path
                // (Groups -> GroupJoin -> Groups) and is itself a safe no-op if Home isn't present.
                onJoined = {
                    navController.navigate(Destinations.Groups.route) {
                        popUpTo(Destinations.Home.route)
                        launchSingleTop = true
                    }
                },
            )
        }

        composable(
            route = Destinations.GroupDetail.route,
            arguments = listOf(navArgument("groupId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val groupId = requireNotNull(backStackEntry.arguments?.getString("groupId"))
            val groupDetailViewModel: GroupDetailViewModel =
                viewModel(factory = GroupDetailViewModelFactory(groupId, container.findlyApiClient))
            GroupDetailRoute(
                viewModel = groupDetailViewModel,
                joinLinkHost = container.appConfig.joinLinkHost,
                onLeft = { navController.popBackStack(Destinations.Groups.route, false) },
                onOpenMap = { id -> navController.navigate(Destinations.GroupMap.createRoute(id)) },
            )
        }

        composable(
            route = Destinations.GroupMap.route,
            arguments = listOf(navArgument("groupId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val groupId = requireNotNull(backStackEntry.arguments?.getString("groupId"))
            val groupMapViewModel: GroupMapViewModel =
                viewModel(factory = GroupMapViewModelFactory(groupId, container.findlyApiClient))
            GroupMapRoute(
                viewModel = groupMapViewModel,
                mapRenderer = container.mapRenderer,
                onExpired = { navController.popBackStack(Destinations.Groups.route, false) },
            )
        }
    }
    }
}
