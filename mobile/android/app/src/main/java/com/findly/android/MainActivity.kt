package com.findly.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.findly.android.location.LocationAuthorization
import com.findly.android.location.LocationAuthorizationResolver
import com.findly.android.location.PermissionBanner
import com.findly.android.location.PermissionDisclosureKind
import com.findly.android.location.PermissionFlowPolicy
import com.findly.android.location.PermissionFlowStep
import com.findly.android.ui.designsystem.components.FindlyPermissionBanner
import com.findly.android.ui.permissions.PermissionDisclosureScreen
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.Modifier
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.viewmodel.compose.viewModel
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.queue.worker.LocationForegroundService
import com.findly.android.ui.groups.GroupJoinHttpsLinkParser
import com.findly.android.ui.invites.FamilyInviteHttpsLinkParser
import com.findly.android.launch.LaunchGateViewModel
import com.findly.android.launch.LaunchGateViewModelFactory
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
 * idiom for "handle this Intent once, not on every recreation."
 *
 * **A36 addition** (specs/007-public-join-links.md §1/§4 as amended 2026-08-26, specs/010 §5.2):
 * the exact same treatment, in parallel, for the public
 * `https://{JOIN_LINK_HOST}/f#CODE` family-invite link via [FamilyInviteHttpsLinkParser] — same
 * fragment-based reasoning, same [savedInstanceState]-gated freshness guard, routing to
 * [com.findly.android.ui.nav.Destinations.InviteAccept] instead of `GroupJoin`. */
class MainActivity : ComponentActivity() {

    private val container get() = (application as FindlyApplication).container

    /** A9 (specs/003-android-client.md §11 point 4; specs/009-device-runtime.md §5.3/§5.1):
     * `POST_NOTIFICATIONS` (API 33+) requested independently of the fine/background location
     * staging sequence (points 1-3 of §11, still unimplemented — a pre-existing gap this task
     * does not close), since geofence/locate push alerts need it regardless of location
     * permission state. The callback is intentionally a no-op either way: denial just means no
     * alert is shown (§5.3's [com.findly.android.pushmessages.GeofenceEventNotifier] already
     * swallows the resulting `SecurityException`), never a crash.
     *
     * TODO(A2): a prominent disclosure before this OS prompt, and a persistent denial banner, are
     * both still missing for every permission in this codebase (009 §7) — not just this one. */
    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* no-op */ }

    /** Bumped after any permission result so the Compose tree re-reads the checkers (009 §7's
     * "re-checked on every foreground", plus immediately after the user answers a dialog). */
    private val permissionEpoch = mutableIntStateOf(0)

    /**
     * specs/003 §11.1 / 009 §7 — the fine-location request. **This app had no location request at
     * all before now**: the permission was declared and checked, but never asked for, so Android
     * could never report a position. Fired only from the disclosure's Continue button.
     */
    private val fineLocationLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            permissionEpoch.intValue++
        }

    /**
     * specs/003 §11.2 — the background upgrade, a **separate, later** request: Android 11+ refuses
     * to show it bundled with the foreground one, and it needs its own rationale first.
     */
    private val backgroundLocationLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            permissionEpoch.intValue++
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        container.onActivityStarted(this)
        // NOT requested here any more (specs/009 §7). Firing it from onCreate put the system
        // notification dialog on screen on top of the location disclosure — the same
        // prompt-before-explanation inversion, one permission over. It now runs from the composable
        // below, only once no disclosure is pending.

        val launchingUri = intent?.data
        val httpsJoinLinkResult = GroupJoinHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = savedInstanceState == null,
            scheme = launchingUri?.scheme,
            host = launchingUri?.host,
            path = launchingUri?.path,
            fragment = launchingUri?.fragment,
            joinLinkHost = container.appConfig.joinLinkHost,
        )
        // A36 (specs/007-public-join-links.md §1/§4 as amended 2026-08-26, specs/010 §5.2): the
        // public https://{JOIN_LINK_HOST}/f#CODE family-invite link, checked the same way and for
        // the same reason as httpsJoinLinkResult above (fragment-carried codes aren't matched by
        // Navigation Compose's own uriPattern placeholder syntax) -- same freshness guard, so
        // rotation/recreation never re-fires the one-time navigation to the accept-invite screen.
        val httpsFamilyInviteLinkResult = FamilyInviteHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = savedInstanceState == null,
            scheme = launchingUri?.scheme,
            host = launchingUri?.host,
            path = launchingUri?.path,
            fragment = launchingUri?.fragment,
            joinLinkHost = container.appConfig.joinLinkHost,
        )
        // specs/009-device-runtime.md §3.2: the foreground-service notification's tap action
        // opens the device-settings screen -- specs/010-app-shell-and-screen-ux.md §4.1's new
        // Devices route (the retired Settings monolith's replacement). Same freshness guard as
        // httpsJoinLinkResult above (savedInstanceState == null) so a rotation/recreation doesn't
        // re-fire the navigation.
        val openDevicesOnLaunch = savedInstanceState == null &&
            intent?.getBooleanExtra(LocationForegroundService.EXTRA_OPEN_DEVICES, false) == true

        setContent {
            FindlyTheme {
                // The app draws edge-to-edge, so without this the top bar renders UNDER the system
                // status bar: the screen title collides with the clock, and the top ~90px of the
                // back chevron sits in the status bar's own tap region — taps there go to the
                // system, not the app, making the upper half of the back button dead. Verified on
                // an emulator 2026-08-05: a tap at y=70 did nothing, y=90 popped correctly.
                // Applied once at the root so every screen inherits it, rather than per-screen —
                // that includes the degraded-state banner below (A25): it is a direct child of this
                // same Box, not a sibling rendered outside it, so it inherits this same inset.
                // displayCutoutPadding() (A25) closes the one system-UI region statusBarsPadding()
                // does NOT cover: on a device whose cutout (notch/punch-hole) extends beyond the
                // reported status-bar height, content could still sit under it otherwise.
                Box(
                    modifier = Modifier
                        .statusBarsPadding()
                        .displayCutoutPadding()
                        .navigationBarsPadding(),
                ) {
                // specs/009 §7 — the disclosure gate. Re-read on every recomposition triggered by
                // `permissionEpoch` (a permission result) and by `ON_RESUME` below, which is §7's
                // "re-checked on every foreground": the user can revoke from system settings at any
                // time, and returning from that screen is the likeliest moment for it to change.
                val epoch = permissionEpoch.intValue
                val lifecycleOwner = LocalLifecycleOwner.current
                DisposableEffect(lifecycleOwner) {
                    val observer = LifecycleEventObserver { _, event ->
                        if (event == Lifecycle.Event.ON_RESUME) permissionEpoch.intValue++
                    }
                    lifecycleOwner.lifecycle.addObserver(observer)
                    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
                }

                var permissionState by remember(epoch) {
                    mutableStateOf(readPermissionState())
                }
                var bannerDismissed by rememberSaveable { mutableStateOf(false) }

                val step = PermissionFlowPolicy.nextStep(
                    authorization = permissionState.authorization,
                    foregroundDisclosureAcknowledged = permissionState.foregroundAcknowledged,
                    foregroundDisclosureDeclined = permissionState.foregroundDeclined,
                    backgroundDisclosureAcknowledged = permissionState.backgroundAcknowledged,
                    backgroundDisclosureDeclined = permissionState.backgroundDeclined,
                    requiresBackground = permissionState.requiresBackground,
                )
                // A25 (009 §7): "Not now" is now persisted (readPermissionState() below), so
                // nextStep() itself already returns None for a declined kind — no more session-only
                // `declinedThisSession` filter here. That in-memory set was exactly the bug: it
                // reset on every cold launch, so a fresh process always saw an empty decline set and
                // re-showed the disclosure regardless of what the user had already answered.
                val pendingDisclosure = (step as? PermissionFlowStep.ShowDisclosure)?.kind

                if (pendingDisclosure != null) {
                    // Full-screen, and returned INSTEAD of the app content: nothing may reach an OS
                    // prompt while this is up — that ordering is the whole of §7 and what Play's
                    // background-location review checks for.
                    PermissionDisclosureScreen(
                        kind = pendingDisclosure,
                        onContinue = {
                            container.permissionDisclosureStore.acknowledge(pendingDisclosure)
                            when (pendingDisclosure) {
                                PermissionDisclosureKind.FOREGROUND ->
                                    fineLocationLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                                PermissionDisclosureKind.BACKGROUND ->
                                    backgroundLocationLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                            }
                            permissionEpoch.intValue++
                        },
                        // A real choice, not a formality: no prompt, no acknowledgement recorded.
                        // A25: now persisted, so it is not re-presented on ANY future launch either
                        // — only the banner's own explicit "reopen" action (below) brings it back.
                        onNotNow = {
                            container.permissionDisclosureStore.decline(pendingDisclosure)
                            permissionEpoch.intValue++
                        },
                    )
                    return@Box
                }

                // Safe to ask now: no disclosure is on screen (that branch returned above).
                LaunchedEffect(Unit) { requestNotificationPermissionIfNeeded() }

                Column {
                    // A25 (009 §7): null means the OS itself already irrevocably refused — the
                    // banner's action routes to system settings there, same as before. A non-null
                    // kind means the OS was never actually asked (the user only declined the in-app
                    // explanation), so the explicit action instead forgets that decline and reopens
                    // the full-screen disclosure, which can still lead to a real OS prompt.
                    val reopenKind = PermissionFlowPolicy.bannerReopenKind(
                        authorization = permissionState.authorization,
                        foregroundDisclosureAcknowledged = permissionState.foregroundAcknowledged,
                        backgroundDisclosureAcknowledged = permissionState.backgroundAcknowledged,
                    )
                    FindlyPermissionBanner(
                        banner = PermissionFlowPolicy.banner(
                            authorization = permissionState.authorization,
                            requiresBackground = permissionState.requiresBackground,
                            foregroundDisclosureDeclined = permissionState.foregroundDeclined,
                            dismissedThisSession = bannerDismissed,
                        ),
                        reopensDisclosure = reopenKind != null,
                        onOpenSettings = { openAppSettings() },
                        onReopenDisclosure = {
                            reopenKind?.let { container.permissionDisclosureStore.clearDeclined(it) }
                            permissionEpoch.intValue++
                        },
                        onDismiss = { bannerDismissed = true },
                    )
                val launchGateViewModel: LaunchGateViewModel = viewModel(
                    factory = LaunchGateViewModelFactory(
                        container.authProvider,
                        container.deviceRegistrar,
                        container.pushTokenProvider,
                        container.findlyApiClient,
                        container.localStateWiper,
                    ),
                )
                // Sign-in navigation lives inside FindlyNavHost itself (specs/003 §7, §12) — it
                // owns the NavController the real path needs.
                FindlyNavHost(
                    container = container,
                    launchGateViewModel = launchGateViewModel,
                    httpsJoinLinkResult = httpsJoinLinkResult,
                    httpsFamilyInviteLinkResult = httpsFamilyInviteLinkResult,
                    openDevicesOnLaunch = openDevicesOnLaunch,
                )
                }
                }
            }
        }
    }

    /** Snapshot of everything [PermissionFlowPolicy] needs, read fresh (never cached — §7). */
    private data class PermissionSnapshot(
        val authorization: LocationAuthorization,
        val foregroundAcknowledged: Boolean,
        val foregroundDeclined: Boolean,
        val backgroundAcknowledged: Boolean,
        val backgroundDeclined: Boolean,
        val requiresBackground: Boolean,
    )

    private fun readPermissionState(): PermissionSnapshot {
        val fine = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val background = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val store = container.permissionDisclosureStore
        val foregroundAcknowledged = store.isAcknowledged(PermissionDisclosureKind.FOREGROUND)
        return PermissionSnapshot(
            authorization = LocationAuthorizationResolver.resolve(
                fineGranted = fine,
                backgroundGranted = background,
                foregroundDisclosureAcknowledged = foregroundAcknowledged,
            ),
            foregroundAcknowledged = foregroundAcknowledged,
            // A25 (009 §7): "Not now" is persisted so it survives a cold launch (isDeclined()),
            // instead of the old in-memory-only `declinedThisSession` set that reset every launch.
            foregroundDeclined = store.isDeclined(PermissionDisclosureKind.FOREGROUND),
            backgroundAcknowledged = store.isAcknowledged(PermissionDisclosureKind.BACKGROUND),
            backgroundDeclined = store.isDeclined(PermissionDisclosureKind.BACKGROUND),
            // Tracking paused means this device is not reporting by choice, so it must not nag for
            // a permission it is not using. Read synchronously here; the flow only needs the
            // coarse answer, not a suspending settings load.
            requiresBackground = true,
        )
    }

    /** specs/009 §7's "route into system settings" — the only way back once permission is refused,
     * since Android will not show its dialog again. */
    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null),
            ),
        )
    }

    override fun onDestroy() {
        container.onActivityStopped(this)
        super.onDestroy()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return // granted at install time below API 33
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
