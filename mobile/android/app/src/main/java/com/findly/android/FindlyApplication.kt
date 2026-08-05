package com.findly.android

import android.app.Application
import androidx.work.Configuration

/**
 * `Configuration.Provider` switches WorkManager to on-demand initialization (androidx.work 2.6+)
 * so [AppContainer.workerFactory] — which constructs `LocationSyncWorker`/`SettingsPollWorker`
 * with their real dependencies (specs/009-device-runtime.md §3) — is used instead of WorkManager's
 * default no-arg-constructor factory.
 *
 * **A15 correction:** implementing this interface alone is *not* sufficient — the default
 * `androidx.startup.InitializationProvider` entry for `WorkManagerInitializer` (contributed by
 * the `androidx.work` library's own manifest) must also be removed from the merged manifest
 * (`AndroidManifest.xml`), or it wins the race: `ContentProvider.onCreate()` runs before
 * `Application.onCreate()`, so `WorkManagerInitializer.create()` — which unconditionally calls
 * `WorkManager.initialize(context, Configuration.Builder().build())` with no check for this
 * interface at all (verified from the `androidx.work:work-runtime:2.10.0` bytecode) — would
 * permanently claim the `WorkManager` singleton with the *default* `WorkerFactory` first.
 * `WorkManagerImpl.getInstance(Context)` only consults `Configuration.Provider` when no instance
 * exists yet, so every later call from [AppContainer] would silently get that already-initialized,
 * wrongly-configured instance back — [AppContainer.workerFactory] would never run, and
 * `LocationSyncWorker`/`SettingsPollWorker` (whose constructors take extra dependency parameters
 * the default reflective factory can't supply) would fail to construct at runtime. See the
 * `<provider android:name="androidx.startup.InitializationProvider">` removal entry in
 * `AndroidManifest.xml` for the actual fix (androidx.work's own documented pattern for this).
 */
class FindlyApplication : Application(), Configuration.Provider {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // MUST come after the assignment above, never from inside AppContainer's constructor:
        // start() touches WorkManager, whose on-demand initialization calls straight back into
        // `workManagerConfiguration` below and reads `container`. See AppContainer.start()'s doc —
        // running it a line earlier was a 100% launch crash.
        container.start()
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(container.workerFactory)
            .build()
}
