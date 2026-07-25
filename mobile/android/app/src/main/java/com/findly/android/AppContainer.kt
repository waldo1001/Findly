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
import com.findly.android.network.RetrofitFactory
import com.findly.android.network.FindlyApiClient
import com.findly.android.push.PushTokenProvider
import com.findly.android.push.StubPushTokenProvider
import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.InMemoryFixQueueStore
import com.findly.android.ui.map.MapRenderer
import com.findly.android.ui.map.PlaceholderMapRenderer
import com.findly.android.ui.settings.DefaultLocalStateWiper
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

    val pushTokenProvider: PushTokenProvider = StubPushTokenProvider()

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

    /** A8 (specs/008-privacy-endpoints.md §4.4; specs/003-android-client.md §12.4): wipes local
     * state after a successful account deletion. See [DefaultLocalStateWiper]'s doc for why only
     * these two stores are wired today. */
    val localStateWiper: LocalStateWiper = DefaultLocalStateWiper(fixQueueStore, deviceIdStore)

    /** A2's live-map tile renderer seam (`ui/map/MapRenderer.kt`) — [PlaceholderMapRenderer] is
     * the only implementation until H1 provisions a real Maps API key (`appConfig.mapsApiKey`). */
    val mapRenderer: MapRenderer = PlaceholderMapRenderer()

    init {
        // 001 §4.1 / 000 §O4: re-POST /devices on every push-token refresh. Fixed wiring point
        // regardless of whether pushTokenProvider is the A1 stub or a real FCM-backed class.
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
    }
}
