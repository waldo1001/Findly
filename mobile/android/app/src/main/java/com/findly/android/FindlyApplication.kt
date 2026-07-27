package com.findly.android

import android.app.Application
import androidx.work.Configuration

/**
 * `Configuration.Provider` switches WorkManager to on-demand initialization (androidx.work 2.6+,
 * no manifest changes needed) so [AppContainer.workerFactory] — which constructs
 * `LocationSyncWorker`/`SettingsPollWorker` with their real dependencies (specs/009-device-runtime.md
 * §3) — is used instead of WorkManager's default no-arg-constructor factory.
 */
class FindlyApplication : Application(), Configuration.Provider {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(container.workerFactory)
            .build()
}
