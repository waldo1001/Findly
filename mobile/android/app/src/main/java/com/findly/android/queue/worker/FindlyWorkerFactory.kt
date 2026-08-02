package com.findly.android.queue.worker

import android.content.Context
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import com.findly.android.location.settings.SettingsPoller

/**
 * Constructs [LocationSyncWorker]/[SettingsPollWorker] with their real, `AppContainer`-wired
 * dependencies — WorkManager's default no-arg-constructor path can't supply these. Registered via
 * `FindlyApplication`'s `Configuration.Provider` (on-demand WorkManager initialization —
 * androidx.work 2.6+, but see [com.findly.android.FindlyApplication]'s A15 doc note: a manifest
 * change removing the default `WorkManagerInitializer` entry is also required, or this factory is
 * silently never used). Providers (not plain instances) because a
 * worker may be constructed at any time — including after the signed-in user has changed — so
 * each construction re-reads whatever `AppContainer` currently considers "the signed-in device".
 * Both providers may return `null` (no signed-in user right now, e.g. a run replayed shortly
 * after sign-out) — the workers themselves treat that as a clean no-op, never a crash.
 */
class FindlyWorkerFactory(
    private val locationSyncRunnerProvider: () -> LocationSyncRunner?,
    private val settingsPollerProvider: () -> SettingsPoller?,
) : WorkerFactory() {

    override fun createWorker(
        appContext: Context,
        workerClassName: String,
        workerParameters: WorkerParameters,
    ): ListenableWorker? = when (workerClassName) {
        LocationSyncWorker::class.java.name ->
            LocationSyncWorker(appContext, workerParameters, locationSyncRunnerProvider())
        SettingsPollWorker::class.java.name ->
            SettingsPollWorker(appContext, workerParameters, settingsPollerProvider())
        else -> null
    }
}
