package com.findly.android

import android.app.Activity
import android.content.Context
import com.google.firebase.auth.FirebaseAuth
import com.findly.android.auth.AuthProvider
import com.findly.android.auth.AuthProviderFactory
import com.findly.android.auth.AuthState
import com.findly.android.auth.CurrentActivityProvider
import com.findly.android.auth.FirebaseAuthProvider
import com.findly.android.config.AppConfig
import com.findly.android.device.AndroidDeviceInfoProvider
import com.findly.android.device.DeviceIdProvider
import com.findly.android.device.DeviceRegistrar
import com.findly.android.device.SharedPreferencesDeviceIdStore
import com.findly.android.location.UnimplementedLocationCapturer
import com.findly.android.network.RetrofitFactory
import com.findly.android.network.FindlyApiClient
import com.findly.android.push.PushTokenProvider
import com.findly.android.push.RealPushTokenProvider
import com.findly.android.pushmessages.GeofenceConfigChangedPushHandler
import com.findly.android.pushmessages.GeofenceEventNotifier
import com.findly.android.pushmessages.GeofenceEventPushHandler
import com.findly.android.pushmessages.LocateRequestPushHandler
import com.findly.android.pushmessages.PushMessageDispatcher
import com.findly.android.pushmessages.SettingsChangedPushHandler
import com.findly.android.pushmessages.UnimplementedGeofenceRegistrar
import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.queue.worker.LocationSyncScheduler
import com.findly.android.queue.worker.ScheduleRebuilder
import com.findly.android.ui.map.GoogleMapRenderer
import com.findly.android.ui.map.MapRenderer
import com.findly.android.ui.settings.ColdStartExportCleanup
import com.findly.android.ui.settings.DefaultLocalStateWiper
import com.findly.android.ui.settings.ExportArtifactCleaner
import com.findly.android.ui.settings.ExportFileWriter
import com.findly.android.ui.settings.LocalStateWiper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Manual, poor-man's DI container (specs/003-android-client.md §3) — no Hilt/Dagger, to keep the
 * A1 foundation's build surface small and avoid an unverifiable KSP/annotation-processor
 * version pairing with no toolchain here to compile-check it (same rationale as skipping Room,
 * §10.4). Thin, untested wiring — mirrors the backend's `src/functions`
 * (backend/README.md's hexagonal split).
 */
class AppContainer(context: Context) {

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val appConfig: AppConfig = AppConfig.fromBuildConfig(
        baseUrl = BuildConfig.BASE_URL,
        authModeValue = BuildConfig.AUTH_MODE,
        firebaseProjectId = BuildConfig.FIREBASE_PROJECT_ID,
        mapsApiKey = BuildConfig.MAPS_API_KEY,
        joinLinkHost = BuildConfig.JOIN_LINK_HOST,
    )

    /** Registered/cleared by `MainActivity` (specs/003 §7) — Firebase phone-auth needs a live
     * `Activity` for Play Integrity / reCAPTCHA app verification; only [FirebaseAuthProvider]
     * consumes this, via [currentActivityProvider]. */
    private var currentActivity: Activity? = null
    private val currentActivityProvider = CurrentActivityProvider { currentActivity }

    fun onActivityStarted(activity: Activity) {
        currentActivity = activity
    }

    fun onActivityStopped(activity: Activity) {
        if (currentActivity === activity) currentActivity = null
    }

    val authProvider: AuthProvider = AuthProviderFactory.create(appConfig.authMode, appConfig.firebaseProjectId) {
        FirebaseAuthProvider(FirebaseAuth.getInstance(), currentActivityProvider)
    }

    val pushTokenProvider: PushTokenProvider = RealPushTokenProvider()

    private val findlyApiService = RetrofitFactory.create(appConfig.baseUrl, authProvider)
    val findlyApiClient: FindlyApiClient = FindlyApiClient(findlyApiService, authProvider)

    private val deviceIdStore = SharedPreferencesDeviceIdStore(context)
    private val deviceIdProvider = DeviceIdProvider(deviceIdStore)
    private val deviceInfoProvider = AndroidDeviceInfoProvider()
    val deviceRegistrar: DeviceRegistrar =
        DeviceRegistrar(findlyApiClient, deviceIdProvider, deviceInfoProvider)

    /** Offline fix-queue (specs/003 §10) — not yet drained by anything; `LocationSyncWorker`
     * wiring is A2/H1 scope (§10.5). */
    val fixQueueStore: FixQueueStore = InMemoryFixQueueStore()

    /** The one `Context`-touching implementation of [ExportArtifactCleaner], shared by both of
     * 008 §3.1 rule 2 (amended)'s non-racing cleanup triggers: [localStateWiper]'s
     * account-deletion wipe, and [coldStartExportCleanup]'s process-restart wipe. */
    private val exportArtifactCleaner = ExportArtifactCleaner { ExportFileWriter.clearArtifacts(context) }

    /** A8 (specs/008-privacy-endpoints.md §4.4/§3.1; specs/003-android-client.md §12.4): wipes
     * local state — fix queue, deviceId, and export artifacts — after a successful account
     * deletion. See [DefaultLocalStateWiper]'s doc for the current scope. */
    val localStateWiper: LocalStateWiper = DefaultLocalStateWiper(
        fixQueueStore = fixQueueStore,
        deviceIdStore = deviceIdStore,
        exportArtifactCleaner = exportArtifactCleaner,
    )

    /** 008 §3.1 rule 2 (amended)'s cold-start trigger — see [ColdStartExportCleanup]'s doc for why
     * a process restart is one of only two safe cleanup triggers left, now that share-sheet
     * return/dismissal and screen teardown are both forbidden (they can race a lazily-reading
     * share target). Run once, below, from `init`. */
    private val coldStartExportCleanup = ColdStartExportCleanup(exportArtifactCleaner)

    /** A12: the real Google Maps tile renderer (`ui/map/MapRenderer.kt`'s seam) — an empty
     * `appConfig.mapsApiKey` (until H1 provisions a real one, docs/azure-setup.md) still renders
     * fine, just with no tiles; `PlaceholderMapRenderer` remains available for
     * Compose previews/tests (specs/003-android-client.md §12.1). */
    val mapRenderer: MapRenderer = GoogleMapRenderer()

    /** A9 (specs/009-device-runtime.md §3): still the A2-scaffolded no-op `schedule()` (see its
     * own doc) — only `cancel()` does anything real today. Shared between `settingsChangedHandler`
     * below and whatever A10 eventually wires up for the other two §3.5 settings-arrival paths. */
    private val locationSyncScheduler = LocationSyncScheduler(context)

    /** A9 (specs/009-device-runtime.md §5): routes every FCM data message to its 001 §8 handler.
     * `FindlyMessagingService` (the real `FirebaseMessagingService`) is this class's one
     * production caller. [UnimplementedLocationCapturer]/[UnimplementedGeofenceRegistrar] are
     * placeholder seams — swapped for real implementations by A10/A11 respectively, no call-site
     * change needed here beyond that one constructor argument. */
    val pushMessageDispatcher: PushMessageDispatcher = PushMessageDispatcher(
        locateRequestHandler = LocateRequestPushHandler(
            locationCapturer = UnimplementedLocationCapturer, // TODO(A10)
            locateApi = findlyApiClient,
            deviceIdProvider = {
                (authProvider.authState.value as? AuthState.SignedIn)?.uid?.let { uid ->
                    deviceRegistrar.deviceIdFor(uid)
                }
            },
        ),
        settingsChangedHandler = SettingsChangedPushHandler(
            scheduleRebuilder = ScheduleRebuilder { syncIntervalMinutes, trackingEnabled ->
                // TODO(A10): apply the full pause sequence (009 §4 - stop worker/service,
                // unregister geofences), not just the schedule call itself.
                if (trackingEnabled) {
                    locationSyncScheduler.schedule(syncIntervalMinutes)
                } else {
                    locationSyncScheduler.cancel()
                }
            },
        ),
        geofenceEventHandler = GeofenceEventPushHandler(GeofenceEventNotifier(context)),
        geofenceConfigChangedHandler = GeofenceConfigChangedPushHandler(
            geofenceApi = findlyApiClient,
            geofenceRegistrar = UnimplementedGeofenceRegistrar, // TODO(A11)
        ),
    )

    init {
        // 001 §4.1 / 000 §O4: re-POST /devices on every push-token refresh. Fixed wiring point,
        // unchanged since the A1 stub was swapped for the real FCM-backed RealPushTokenProvider.
        pushTokenProvider.addRefreshListener { token ->
            val uid = (authProvider.authState.value as? AuthState.SignedIn)?.uid
            if (uid != null) {
                applicationScope.launch {
                    // TODO(A2): surface failures via a retry/backoff policy instead of
                    // fire-and-forget.
                    deviceRegistrar.onPushTokenRefreshed(uid, token)
                }
            }
        }

        // 008 §3.1 rule 2 (amended): an export artifact must never survive a process restart.
        // `AppContainer` is constructed exactly once per process, in `FindlyApplication.onCreate`
        // (never per-Activity/per-screen), so this is the one true "next app cold start" hook.
        coldStartExportCleanup.run()
    }
}
