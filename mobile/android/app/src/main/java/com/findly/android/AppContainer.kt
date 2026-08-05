package com.findly.android

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.room.Room
import com.google.android.gms.location.LocationServices
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
import com.findly.android.location.AndroidBackgroundLocationPermissionChecker
import com.findly.android.location.AndroidBatteryLevelProvider
import com.findly.android.location.AndroidLocationPermissionChecker
import com.findly.android.location.FixCaptureCoordinator
import com.findly.android.location.FusedLocationCapturer
import com.findly.android.location.LocationCapturer
import com.findly.android.location.TrackingPauseState
import com.findly.android.location.geofence.GeofenceTransitionHandler
import com.findly.android.location.geofence.GeofenceTransitionReceiver
import com.findly.android.location.geofence.GeofencingClientManager
import com.findly.android.location.settings.DeviceSettingsCoordinator
import com.findly.android.location.settings.DeviceSettingsStateStore
import com.findly.android.location.settings.GeofenceConfigStateStore
import com.findly.android.location.settings.GeofenceConfigSyncCoordinator
import com.findly.android.location.settings.GeofenceRegistry
import com.findly.android.location.settings.SettingsPoller
import com.findly.android.location.settings.SharedPreferencesDeviceSettingsStateStore
import com.findly.android.location.settings.SharedPreferencesGeofenceConfigStateStore
import com.findly.android.location.settings.SyncScheduler
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
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
import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.GeofenceEventQueueStore
import com.findly.android.queue.GeofenceEventSyncCoordinator
import com.findly.android.queue.LocationSyncCoordinator
import com.findly.android.queue.room.FindlyDatabase
import com.findly.android.queue.room.MIGRATION_1_2
import com.findly.android.queue.room.RoomFixQueueStore
import com.findly.android.queue.room.RoomGeofenceEventQueueStore
import com.findly.android.queue.worker.DefaultForegroundServiceController
import com.findly.android.queue.worker.FindlyWorkerFactory
import com.findly.android.queue.worker.LastCaptureDateStore
import com.findly.android.queue.worker.LocationSyncRunner
import com.findly.android.queue.worker.LocationSyncScheduler
import com.findly.android.queue.worker.ScheduleRebuilder
import com.findly.android.queue.worker.SettingsPollScheduler
import com.findly.android.queue.worker.SharedPreferencesLastCaptureDateStore
import com.findly.android.ui.map.GoogleMapRenderer
import com.findly.android.ui.map.MapRenderer
import com.findly.android.ui.settings.ColdStartExportCleanup
import com.findly.android.ui.settings.DefaultLocalStateWiper
import com.findly.android.ui.settings.ExportArtifactCleaner
import com.findly.android.ui.settings.ExportFileWriter
import com.findly.android.ui.settings.LocalStateWiper
import java.time.LocalDate
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
        // specs/009-device-runtime.md §4: "re-check settings... on every app foreground".
        onAppForeground()
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

    /** A10 (specs/009-device-runtime.md §2): durable, Room-backed offline fix-queue — replaces
     * the A1 in-memory placeholder (specs/003 §10.4) behind the unchanged [FixQueueStore]
     * interface. One drop event per overflow is logged at debug level with a **count only**
     * (never coordinates, docs/security-review-checklist.md). A11 adds the `geofence_events`
     * table to the same database (queue/room/FindlyDatabase.kt) — version 1 -> 2, via the real
     * [MIGRATION_1_2] (code-review fix, post-A11 review: `fallbackToDestructiveMigration` would
     * have silently wiped this pre-existing `fixes` table on every upgrade too, not just the new
     * empty one). */
    private val findlyDatabase = Room.databaseBuilder(context, FindlyDatabase::class.java, FindlyDatabase.DATABASE_NAME)
        .addMigrations(MIGRATION_1_2)
        .build()
    val fixQueueStore: FixQueueStore = RoomFixQueueStore(
        dao = findlyDatabase.fixQueueDao(),
        onOverflowDropped = { droppedCount ->
            Log.d("FindlyFixQueue", "1000-fix cap reached, dropped $droppedCount oldest fix(es)")
        },
    )

    /** A11 (specs/009-device-runtime.md §6.3): durable, Room-backed geofence-event queue — same
     * database, same durability bar as [fixQueueStore]. */
    val geofenceEventQueueStore: GeofenceEventQueueStore = RoomGeofenceEventQueueStore(findlyDatabase.geofenceEventDao())

    /** A10 (specs/009 §3.5/§4): the settings-application entry point — **this is the seam A9's
     * `SETTINGS_CHANGED` push handler calls**, alongside the `POST /locations` piggyback
     * ([LocationSyncRunner], via [com.findly.android.queue.worker.SyncOutcomeReactor]) and the
     * paused-device poll ([settingsPoller] below). */
    private val deviceSettingsStateStore: DeviceSettingsStateStore = SharedPreferencesDeviceSettingsStateStore(context)

    /** A11 (specs/009-device-runtime.md §6.1): the cached geofence config document + ETag —
     * `GeofenceConfigSyncCoordinator`'s source of truth for `If-None-Match` and for re-registering
     * from cache on a `304`/failed fetch (resume, cold start). */
    private val geofenceConfigStateStore: GeofenceConfigStateStore = SharedPreferencesGeofenceConfigStateStore(context)

    /** A11 (specs/009 §6.2): the `PendingIntent` GeofencingClient fires on every enter/exit
     * transition, targeting [GeofenceTransitionReceiver]. `FLAG_MUTABLE` is required — the system
     * attaches the `GeofencingEvent` extras onto this exact `Intent` when it fires. */
    private val geofenceTransitionPendingIntent: PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, GeofenceTransitionReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )

    /** A11 (specs/009 §6.2): the one real class implementing both [GeofenceRegistry] and
     * [com.findly.android.pushmessages.GeofenceRegistrar] — A10's report predicted this shape.
     * Pause (§4) calls `unregisterAll()` through the [GeofenceRegistry] half; every §6.2
     * registration trigger calls `registerAll(...)` (a full replace) through the
     * [com.findly.android.pushmessages.GeofenceRegistrar] half, via [geofenceConfigSyncCoordinator]. */
    private val geofencingClientManager = GeofencingClientManager(
        geofencingClient = LocationServices.getGeofencingClient(context),
        pendingIntent = geofenceTransitionPendingIntent,
        permissionState = AndroidBackgroundLocationPermissionChecker(context),
        scope = applicationScope,
    )
    private val geofenceRegistry: GeofenceRegistry = geofencingClientManager

    /** A11 (specs/009 §6.2): the consolidated fetch-cache-register sequence — every one of the
     * five registration triggers (first sync after sign-in, an observed ETag change, the
     * `GEOFENCE_CONFIG_CHANGED` push, resume from pause, and app cold start below) calls
     * [GeofenceConfigSyncCoordinator.sync] or [GeofenceConfigSyncCoordinator.syncIfEtagChanged]
     * on this single instance. */
    val geofenceConfigSyncCoordinator = GeofenceConfigSyncCoordinator(
        geofenceApi = findlyApiClient,
        geofenceConfigStore = geofenceConfigStateStore,
        geofenceRegistrar = geofencingClientManager,
    )

    private val foregroundServiceController = DefaultForegroundServiceController(context)
    private val syncScheduler: SyncScheduler = LocationSyncScheduler(context, foregroundServiceController)

    /** A11 (specs/009 §6.2): resume from pause is one of the five geofence re-registration
     * triggers — wired here as [DeviceSettingsCoordinator]'s `onResume` seam so a
     * `SETTINGS_CHANGED`/piggyback/poll-driven resume gets the full sequence (schedule rebuild
     * *and* geofence re-registration) for free. */
    val deviceSettingsCoordinator = DeviceSettingsCoordinator(
        syncScheduler,
        geofenceRegistry,
        deviceSettingsStateStore,
        onResume = { geofenceConfigSyncCoordinator.sync() },
    )

    /** [DeviceRegistrar.onRegistered] applies the response's settings immediately (specs/009 §6.2:
     * "first config sync after sign-in") — the same [DeviceSettingsCoordinator.applySettings]
     * entry point every other settings-arrival path uses. A11: also runs the first geofence config
     * sync when the device isn't paused (registering while paused must not re-register geofences —
     * pause's own contract is "zero geofences registered"). */
    val deviceRegistrar: DeviceRegistrar = DeviceRegistrar(
        findlyApiClient,
        deviceIdProvider,
        deviceInfoProvider,
        onRegistered = { device ->
            deviceSettingsCoordinator.applySettings(
                DeviceSettingsSnapshot(device.syncIntervalMinutes, device.trackingEnabled),
            )
            if (device.trackingEnabled) geofenceConfigSyncCoordinator.sync()
        },
    )

    private val batteryLevelProvider = AndroidBatteryLevelProvider(context)
    private val locationPermissionState = AndroidLocationPermissionChecker(context)

    /** Real [TrackingPauseState] — reads the same cache [deviceSettingsCoordinator] writes to, so
     * a pause takes effect for the very next capture attempt with no extra signal needed (specs/009
     * §1.2's "stop capturing" — see `DeviceSettingsCoordinator`'s doc for the full ordering
     * argument). */
    private val trackingPauseState = TrackingPauseState { deviceSettingsStateStore.current()?.trackingEnabled == false }

    /** A9's [LocationCapturer] seam (specs/009 §1.1), now backed by the real
     * `FusedLocationProviderClient` — shared by [fixCaptureCoordinator] below (periodic/manual,
     * suppression-gated) and `pushMessageDispatcher`'s `LocateRequestPushHandler` (locate,
     * deliberately ungated — see [LocationCapturer]'s doc). */
    private val locationCapturer: LocationCapturer =
        FusedLocationCapturer(LocationServices.getFusedLocationProviderClient(context), batteryLevelProvider)

    /** A10 (specs/009 §1): the real capture-and-queue pipeline — **this is the seam A11's
     * geofence-transition handling calls** for its `source: "geofence"` fix
     * (`fixCaptureCoordinator.captureAndQueue(FixSource.Geofence, hint = ...)`). */
    val fixCaptureCoordinator = FixCaptureCoordinator(
        capturer = locationCapturer,
        queueStore = fixQueueStore,
        pauseState = trackingPauseState,
        permissionState = locationPermissionState,
    )

    /** A11 (specs/009 §6.3): the tested decision logic behind a `GeofencingClient` enter/exit
     * callback — **this is the seam [GeofenceTransitionReceiver] calls**, via
     * `container.geofenceTransitionHandler`. Must be public for that receiver (a separate
     * `BroadcastReceiver`-constructed component, not part of this container's own object graph)
     * to reach it. */
    val geofenceTransitionHandler = GeofenceTransitionHandler(
        eventQueueStore = geofenceEventQueueStore,
        fixCaptureCoordinator = fixCaptureCoordinator,
        batteryLevelProvider = batteryLevelProvider,
        pauseState = trackingPauseState,
    )

    private val lastCaptureDateStore: LastCaptureDateStore = SharedPreferencesLastCaptureDateStore(context)
    private val settingsPollScheduler = SettingsPollScheduler(context)

    /** Resolves the signed-in user's stable per-uid `deviceId` (specs/001-api-contract.md §1.4) —
     * `null` when nobody is signed in. Backs both [locationSyncRunnerOrNull] and
     * [settingsPollerOrNull], which every real trigger (WorkManager, the foreground service, app
     * foreground) goes through rather than each re-deriving it. */
    private fun currentDeviceIdOrNull(): String? =
        (authProvider.authState.value as? AuthState.SignedIn)?.uid?.let { deviceIdProvider.deviceIdFor(it) }

    /** Built fresh on every call (never cached) so it always reflects whoever is currently
     * signed in — see [FindlyWorkerFactory]'s doc for why. */
    fun locationSyncRunnerOrNull(): LocationSyncRunner? {
        val deviceId = currentDeviceIdOrNull() ?: return null
        return LocationSyncRunner(
            currentSyncIntervalMinutes = { deviceSettingsStateStore.current()?.syncIntervalMinutes ?: DEFAULT_SYNC_INTERVAL_MINUTES },
            lastCaptureDateStore = lastCaptureDateStore,
            today = LocalDate::now,
            captureCoordinator = fixCaptureCoordinator,
            syncCoordinator = LocationSyncCoordinator(fixQueueStore, findlyApiClient, deviceId),
            geofenceEventSyncCoordinator = GeofenceEventSyncCoordinator(geofenceEventQueueStore, findlyApiClient, deviceId),
            settingsCoordinator = deviceSettingsCoordinator,
            geofenceConfigSyncCoordinator = geofenceConfigSyncCoordinator,
            // specs/009 §9: DEVICE_NOT_FOUND -> stop the schedule, clear local device state,
            // re-run registration; if that also fails, treat as signed-out.
            onReRegisterDevice = {
                syncScheduler.cancelAll()
                val uid = (authProvider.authState.value as? AuthState.SignedIn)?.uid
                if (uid == null) {
                    authProvider.signOut()
                } else {
                    deviceIdStore.clear(uid)
                    val result = deviceRegistrar.registerOrUpdate(uid)
                    if (result is ApiResult.Failure) authProvider.signOut()
                }
            },
            // specs/009 §9: a second AUTH_TOKEN_EXPIRED (the retry-once path already failed once,
            // specs/003 §6.4) means signed-out.
            onSignedOut = {
                syncScheduler.cancelAll()
                authProvider.signOut()
            },
        )
    }

    fun settingsPollerOrNull(): SettingsPoller? {
        val deviceId = currentDeviceIdOrNull() ?: return null
        return SettingsPoller(findlyApiClient, deviceId, deviceSettingsCoordinator)
    }

    /** Registered with WorkManager via `FindlyApplication`'s `Configuration.Provider`. */
    val workerFactory = FindlyWorkerFactory(
        locationSyncRunnerProvider = ::locationSyncRunnerOrNull,
        settingsPollerProvider = ::settingsPollerOrNull,
    )

    /** specs/009 §4: "re-check settings... on every app foreground" — `MainActivity`/
     * [onActivityStarted] calls this. Harmless no-op when not paused. */
    fun onAppForeground() {
        applicationScope.launch { settingsPollerOrNull()?.poll() }
    }

    private companion object {
        const val DEFAULT_SYNC_INTERVAL_MINUTES = 15
    }

    /** The one `Context`-touching implementation of [ExportArtifactCleaner], shared by both of
     * 008 §3.1 rule 2 (amended)'s non-racing cleanup triggers: [localStateWiper]'s
     * account-deletion wipe, and [coldStartExportCleanup]'s process-restart wipe. */
    private val exportArtifactCleaner = ExportArtifactCleaner { ExportFileWriter.clearArtifacts(context) }

    /** A8 (specs/008-privacy-endpoints.md §4.4/§3.1; specs/003-android-client.md §12.4): wipes
     * local state — fix queue, deviceId, export artifacts, and (A11) the geofence-event queue and
     * cached geofence config/ETag — after a successful account deletion. See
     * [DefaultLocalStateWiper]'s doc for the current scope. */
    val localStateWiper: LocalStateWiper = DefaultLocalStateWiper(
        fixQueueStore = fixQueueStore,
        deviceIdStore = deviceIdStore,
        exportArtifactCleaner = exportArtifactCleaner,
        geofenceEventQueueStore = geofenceEventQueueStore,
        geofenceConfigStateStore = geofenceConfigStateStore,
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

    /** A9 (specs/009-device-runtime.md §5): routes every FCM data message to its 001 §8 handler.
     * `FindlyMessagingService` (the real `FirebaseMessagingService`) is this class's one
     * production caller. [locationCapturer] and [deviceSettingsCoordinator] are A10's real
     * implementations of A9's placeholder seams (`UnimplementedLocationCapturer`/
     * `ScheduleRebuilder`'s TODO body); A11 wires [geofenceConfigSyncCoordinator] into
     * `GEOFENCE_CONFIG_CHANGED` the same way. */
    val pushMessageDispatcher: PushMessageDispatcher = PushMessageDispatcher(
        locateRequestHandler = LocateRequestPushHandler(
            locationCapturer = locationCapturer,
            locateApi = findlyApiClient,
            deviceIdProvider = {
                (authProvider.authState.value as? AuthState.SignedIn)?.uid?.let { uid ->
                    deviceRegistrar.deviceIdFor(uid)
                }
            },
        ),
        settingsChangedHandler = SettingsChangedPushHandler(
            // specs/009 §3.5 path 1 - the same DeviceSettingsCoordinator.applySettings entry
            // point every other settings-arrival path uses, so SETTINGS_CHANGED gets the full
            // §4 pause sequence (stop worker/service, unregister geofences) for free, not just a
            // bare schedule call.
            scheduleRebuilder = ScheduleRebuilder { syncIntervalMinutes, trackingEnabled ->
                applicationScope.launch {
                    deviceSettingsCoordinator.applySettings(
                        DeviceSettingsSnapshot(syncIntervalMinutes, trackingEnabled),
                    )
                }
            },
        ),
        geofenceEventHandler = GeofenceEventPushHandler(GeofenceEventNotifier(context)),
        geofenceConfigChangedHandler = GeofenceConfigChangedPushHandler(geofenceConfigSyncCoordinator),
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

    /**
     * Cold-start work that must NOT run inside the constructor. Called by
     * [FindlyApplication.onCreate] immediately after `container` is assigned.
     *
     * **Why this is separate — it was a 100% launch crash.** `settingsPollScheduler.ensureScheduled()`
     * calls `WorkManager.getInstance()`. Since A15 removed `WorkManagerInitializer` (so the custom
     * `WorkerFactory` is actually used), that first call performs *on-demand* initialization, which
     * calls back into `FindlyApplication.workManagerConfiguration` → `container.workerFactory`. Run
     * from the constructor, `container` is still unassigned at that moment, so the `lateinit` read
     * threw:
     *
     *     kotlin.UninitializedPropertyAccessException: lateinit property container has not been
     *     initialized
     *       FindlyApplication.getWorkManagerConfiguration → WorkManagerImpl.getInstance
     *       → SettingsPollScheduler.ensureScheduled → AppContainer.<init>
     *
     * A15 fixed a real bug (the default initializer winning the singleton and ignoring the custom
     * factory) and introduced this one, because the two halves are the same mechanism seen from
     * opposite ends: making initialization on-demand is exactly what makes it re-enter the app
     * during construction. Reproduced deterministically on an emulator 2026-08-05 — every launch,
     * debug and release alike. It survived because the Android app had never actually been
     * *launched* since A15; unit tests and `assembleDebug` both pass against a process that dies
     * before `onCreate` returns.
     */
    fun start() {
        // specs/009-device-runtime.md §4: the low-frequency (>=6h) half of the pull-based resume
        // poll must keep running independent of pause/sign-in state (it's the one thing that
        // detects resume) - ExistingPeriodicWorkPolicy.KEEP inside makes this call idempotent, and
        // SettingsPollWorker itself no-ops cleanly while signed out (settingsPollerOrNull() null).
        settingsPollScheduler.ensureScheduled()

        // specs/009 §6.2: device reboot / app reinstall both lose OS-level geofence registrations
        // without changing anything server-side. `AppContainer` is constructed exactly once per
        // process (see coldStartExportCleanup's doc above) - re-checking/re-registering here on
        // every cold start if trackingEnabled covers both events without needing a
        // BOOT_COMPLETED receiver+permission. A fresh install/never-synced device (no cached
        // settings yet) has nothing to restore - `current()?.trackingEnabled == true` is false in
        // that case, so this is a no-op until the "first sync after sign-in" trigger above fires.
        applicationScope.launch {
            if (deviceSettingsStateStore.current()?.trackingEnabled == true) {
                geofenceConfigSyncCoordinator.sync()
            }
        }
    }
}
