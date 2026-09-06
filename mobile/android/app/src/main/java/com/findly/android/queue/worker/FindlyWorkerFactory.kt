package com.findly.android.queue.worker

import android.content.Context
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import com.findly.android.location.settings.SettingsPoller
import com.findly.android.pushmessages.LocateRequestPushHandler

/**
 * Constructs [LocationSyncWorker]/[SettingsPollWorker]/[LocateRequestWorker] with their real,
 * `AppContainer`-wired dependencies — WorkManager's default no-arg-constructor path can't supply
 * these. Registered via `FindlyApplication`'s `Configuration.Provider` (on-demand WorkManager
 * initialization — androidx.work 2.6+, but see [com.findly.android.FindlyApplication]'s A15 doc
 * note: a manifest change removing the default `WorkManagerInitializer` entry is also required, or
 * this factory is silently never used). The first two are providers (not plain instances) because
 * a worker may be constructed at any time — including after the signed-in user has changed — so
 * each construction re-reads whatever `AppContainer` currently considers "the signed-in device".
 * All three providers may return `null` (no signed-in user right now, e.g. a run replayed shortly
 * after sign-out) — the workers themselves treat that as a clean no-op, never a crash.
 * [locateRequestPushHandlerProvider] doesn't depend on "the signed-in device" the same way (its
 * own `deviceIdProvider` seam re-reads that at call time, specs/009 §5.1) but stays a provider for
 * the same construct-fresh-every-time consistency as the other two.
 */
class FindlyWorkerFactory(
    private val locationSyncRunnerProvider: () -> LocationSyncRunner?,
    private val settingsPollerProvider: () -> SettingsPoller?,
    private val locateRequestPushHandlerProvider: () -> LocateRequestPushHandler?,
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
        LocateRequestWorker::class.java.name ->
            LocateRequestWorker(appContext, workerParameters, locateRequestPushHandlerProvider())
        else -> null
    }
}
