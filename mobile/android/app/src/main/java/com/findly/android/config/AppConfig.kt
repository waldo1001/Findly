package com.findly.android.config

import com.findly.android.auth.AuthMode

/**
 * Typed wrapper over `BuildConfig`'s `BASE_URL`/`AUTH_MODE`/`FIREBASE_PROJECT_ID`/`MAPS_API_KEY`
 * fields (specs/003-android-client.md §13). H1 supplies real values once `docs/azure-setup.md`
 * has been run against a real Function App + Firebase project (+ a Google Maps API key, A2's
 * `MapRenderer` seam); nothing here changes when that happens — only the `buildConfigField`
 * values in `app/build.gradle.kts`.
 *
 * @property mapsApiKey empty string until H1 provisions a real key. Sourced from the
 *   `MAPS_API_KEY` Gradle project property (`-PMAPS_API_KEY=…`, wired from the CI secret in H10 —
 *   see `.github/workflows/android.yml` — or a local, gitignored `gradle.properties` override;
 *   see `app/build.gradle.kts`'s `mapsApiKey` local val and `docs/security-review-checklist.md`
 *   §5), **never** hardcoded or committed. H10 correction: `local.properties` does **not** work
 *   here — `project.findProperty` never reads it (that file is parsed only by the Android Gradle
 *   Plugin itself, for SDK-location settings); a previous version of this doc comment wrongly
 *   claimed otherwise. This field exists for completeness/parity with the other `BuildConfig`
 *   wrappers, but A12's
 *   [com.findly.android.ui.map.GoogleMapRenderer] does NOT read it — the Google Maps SDK reads
 *   the key once, at process start, straight from the manifest's `com.google.android.geo.API_KEY`
 *   meta-data (fed by the same Gradle property via `manifestPlaceholders["mapsApiKey"]`). Blank
 *   means "no real key configured yet" — the map still builds and runs, it simply renders a
 *   tile-less grey surface.
 * @property joinLinkHost the public join-link deployment constant (specs/007-public-join-links.md
 *   §1, specs/003-android-client.md §12.3, A6) — `https://{joinLinkHost}/g#{CODE}`. Recorded at
 *   provisioning time (H4, done 2026-07-22 — see `app/build.gradle.kts`'s `joinLinkHost` val for
 *   the real value). Unlike `BASE_URL`/`FIREBASE_PROJECT_ID`, debug and release intentionally
 *   share one value: the join-link surface has no dev mode (specs/003 §12.3).
 */
data class AppConfig(
    val baseUrl: String,
    val authMode: AuthMode,
    val firebaseProjectId: String,
    val mapsApiKey: String = "",
    val joinLinkHost: String = "",
) {
    companion object {
        fun fromBuildConfig(
            baseUrl: String,
            authModeValue: String,
            firebaseProjectId: String,
            mapsApiKey: String = "",
            joinLinkHost: String = "",
        ): AppConfig = AppConfig(
            baseUrl = baseUrl,
            authMode = AuthMode.fromBuildConfigValue(authModeValue),
            firebaseProjectId = firebaseProjectId,
            mapsApiKey = mapsApiKey,
            joinLinkHost = joinLinkHost,
        )
    }
}
