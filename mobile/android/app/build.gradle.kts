// H1 CI note (2026-07-20): `org.jetbrains.kotlin.android` removed — AGP 9.0+ built-in Kotlin
// support makes it redundant (and a hard error to apply alongside it); see build.gradle.kts.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    // H1 (specs/003 §13): requires app/google-services.json (gitignored, real file supplied by
    // the user from the Firebase console) to be present at build time.
    id("com.google.gms.google-services")
    // A10 (specs/009-device-runtime.md §2): Room's annotation processor (queue/room/).
    id("com.google.devtools.ksp")
}

// A2/A12 (specs/003-android-client.md §13, `ui/map/MapRenderer.kt`): the real map-tile SDK
// (A12's GoogleMapRenderer, com.google.maps.android:maps-compose below) needs a Google Maps API
// key that only exists once H1 (docs/azure-setup.md) provisions one. Read from a Gradle project
// property so it can be supplied via `-PMAPS_API_KEY=...` (CI secret, wired in H10 — see
// .github/workflows/android.yml) or a local, gitignored `gradle.properties` override (project
// root `mobile/android/gradle.properties` — gitignored per-user, or the user-global
// `~/.gradle/gradle.properties`) — NEVER hardcoded here and NEVER committed
// (docs/security-review-checklist.md §5).
//
// H10 correction: `project.findProperty` reads Gradle project properties — `-P` flags, this
// project's own `gradle.properties`, `~/.gradle/gradle.properties`, or `ORG_GRADLE_PROJECT_*`
// env vars — it does **not** read `local.properties` (that file is only ever parsed by the
// Android Gradle Plugin itself, for SDK-location-style settings, and is never exposed as a
// Gradle project property). A previous version of this comment claimed `local.properties` was
// a valid place to set `MAPS_API_KEY`; that was wrong and cost real debugging time chasing a
// blank map with the key sitting in the wrong file. Use `~/.gradle/gradle.properties` for a
// local override instead.
//
// Empty string is the correct, safe default: the Maps SDK reads this (via the manifest
// meta-data below) at process start and simply renders a tile-less grey map when it's blank —
// no code branches on its presence.
val mapsApiKey: String = (project.findProperty("MAPS_API_KEY") as String?).orEmpty()

// A7 (docs/store-readiness.md §1): release-signing material must never be hardcoded or
// committed. Values are sourced from an environment variable (CI — see
// .github/workflows/android.yml, which decodes the ANDROID_KEYSTORE_BASE64 secret to a file at
// build time and passes the other three as env vars too) or a Gradle property (local dev
// override via `-PandroidKeystorePath=...` etc., or a gitignored local `gradle.properties` —
// never a tracked file; `keystore.properties`/`*.jks` are already gitignored above for this
// reason). Env var wins when both are set.
//
// When none of this is present — local dev with no keystore yet, PRs (fork or same-repo, where
// this signingConfig is simply never exercised), or any CI run before H5 provisions the real
// secrets — `hasReleaseSigningMaterial` is false and the release build type below falls back to
// the auto-generated debug signingConfig, so `assembleRelease` always succeeds. That fallback
// artifact is signed with the debug keystore only and must never be uploaded to Play Console;
// it exists purely so CI/local dev never fails for lack of a secret they don't need yet.
fun releaseSigningValue(envVar: String, gradleProperty: String): String? =
    System.getenv(envVar)?.takeIf { it.isNotBlank() }
        ?: (project.findProperty(gradleProperty) as String?)?.takeIf { it.isNotBlank() }

val releaseKeystorePath: String? = releaseSigningValue("ANDROID_KEYSTORE_PATH", "androidKeystorePath")
val releaseKeystorePassword: String? = releaseSigningValue("ANDROID_KEYSTORE_PASSWORD", "androidKeystorePassword")
val releaseKeyAlias: String? = releaseSigningValue("ANDROID_KEY_ALIAS", "androidKeyAlias")
val releaseKeyPassword: String? = releaseSigningValue("ANDROID_KEY_PASSWORD", "androidKeyPassword")

// Pure boolean decision, deliberately free of Gradle APIs beyond the nullable strings above —
// true only when every piece of real release-signing material is present and non-blank.
val hasReleaseSigningMaterial: Boolean =
    listOf(releaseKeystorePath, releaseKeystorePassword, releaseKeyAlias, releaseKeyPassword)
        .all { !it.isNullOrBlank() }

// A6 (specs/007-public-join-links.md §1, specs/003-android-client.md §12.3): the public join-link
// host is a deployment constant recorded at provisioning time (H4, docs/azure-setup.md §7) — the
// join-link SWA (`swa-findly`, resource group Findly) was provisioned 2026-07-22; this
// is its real default hostname. Read into BOTH BuildConfig.JOIN_LINK_HOST (Kotlin code, AppConfig)
// and the manifest's ${joinLinkHost} placeholder (AndroidManifest.xml's https intent-filter) from
// this single value so the two can never drift apart. Debug and release intentionally share one
// value (unlike BASE_URL/AUTH_MODE) — the join-link surface has no dev mode (specs/003 §12.3).
val joinLinkHost: String = "kind-plant-0fb99b003.7.azurestaticapps.net"

// H10 (docs/implementation-handoff.md): Play rejects a reused versionCode, and until now it was
// bumped by hand on every release (0.1.0/1 -> 1.0.0 (6) -> 1.0.0 (7), 2026-08-06) — exactly the
// toil this task exists to remove. `.github/workflows/android.yml` now passes
// `-PVERSION_CODE=<n>` for the actual Play-publishing build, derived from
// `100 + github.run_number` (that workflow's own run counter, which only ever increases — see
// the workflow file for the arithmetic showing the next CI run already clears the last
// hand-edited value of 7 by a wide margin). Local dev and any CI run that doesn't pass the
// property (PRs, forks, pre-H10 workflow runs) fall back to the literal below unchanged, so
// nobody's local build breaks or needs updating for this.
val ciVersionCode: Int? = (project.findProperty("VERSION_CODE") as String?)?.toIntOrNull()

android {
    namespace = "com.findly.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.findly.android"
        minSdk = 26
        targetSdk = 37
        // H10: was a hand-edited literal (last value 7, see git history for the 6->7 bump). Now
        // CI-derived when `-PVERSION_CODE` is supplied (see val ciVersionCode above); the literal
        // fallback below is what a local `./gradlew assembleRelease`/`bundleRelease` still uses
        // unchanged, and is intentionally left at the last real shipped value rather than bumped,
        // since a local build is never what gets uploaded to Play.
        versionCode = ciVersionCode ?: 7
        versionName = "1.1.0"
    }

    // A7 (docs/store-readiness.md §1): defined unconditionally (Gradle requires the DSL block to
    // exist to reference it from buildTypes below), but only populated with real values when
    // `hasReleaseSigningMaterial` is true — see the comment above `releaseSigningValue`.
    signingConfigs {
        create("release") {
            if (hasReleaseSigningMaterial) {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
            // else: left unconfigured. buildTypes.release never assigns this instance as its
            // signingConfig in that case (falls back to signingConfigs["debug"] instead), so an
            // incomplete signingConfig here is never actually used to sign anything.
        }
    }

    buildTypes {
        debug {
            // Android emulator's documented loopback alias to the host machine, where
            // `func start` (backend/README.md) listens locally — not a third-party URL, and not
            // reachable outside the emulator. See network_security_config.xml for the matching
            // cleartext carve-out, and specs/003-android-client.md §13 for the H1 hand-off.
            buildConfigField("String", "BASE_URL", "\"http://10.0.2.2:7071/api/\"")
            buildConfigField("String", "AUTH_MODE", "\"insecure-local\"")
            buildConfigField("String", "FIREBASE_PROJECT_ID", "\"findly-dev-placeholder\"")
            buildConfigField("String", "MAPS_API_KEY", "\"$mapsApiKey\"")
            buildConfigField("String", "JOIN_LINK_HOST", "\"$joinLinkHost\"")
            manifestPlaceholders["joinLinkHost"] = joinLinkHost
            manifestPlaceholders["mapsApiKey"] = mapsApiKey
        }
        release {
            // A7: real release signing when CI/local supplies all four values above; otherwise
            // fall back to the auto-generated debug keystore so this build type always builds
            // (docs/store-readiness.md §1 — "PR builds and local dev never fail for lack of a
            // secret they don't need yet").
            signingConfig = if (hasReleaseSigningMaterial) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Enabled 2026-08-05 (was false with a TODO to enable "before shipping"). Turned on
            // while an emulator exists to verify against — enabling R8 late is precisely when
            // reflection-dependent libraries (kotlinx.serialization, Firebase) break, and doing
            // that under submission pressure is how a release slips. See proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Obviously-fake placeholder host (never resolves) — TODO(H1) replaces with the real
            // Function App URL once docs/azure-setup.md has been run (specs/003 §13).
            buildConfigField("String", "BASE_URL", "\"https://func-findly.azurewebsites.net/api/\"")
            buildConfigField("String", "AUTH_MODE", "\"firebase\"")
            buildConfigField("String", "FIREBASE_PROJECT_ID", "\"findly-71f7b\"")
            buildConfigField("String", "MAPS_API_KEY", "\"$mapsApiKey\"")
            buildConfigField("String", "JOIN_LINK_HOST", "\"$joinLinkHost\"")
            manifestPlaceholders["joinLinkHost"] = joinLinkHost
            manifestPlaceholders["mapsApiKey"] = mapsApiKey
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            isIncludeAndroidResources = false
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // A15 (docs/store-readiness.md §1; androidx.activity's InvalidFragmentVersionForActivityResult
    // lint check): this app has no Fragment usage of its own (Compose only, single ComponentActivity)
    // and never declares androidx.fragment directly, but MainActivity's registerForActivityResult
    // (specs/003-android-client.md §11 point 4) needs Fragment >= 1.3.0 in the *resolved* graph
    // regardless. Verified via `gradle :app:dependencies --configuration releaseRuntimeClasspath`
    // that com.google.android.gms:play-services-base (pulled in transitively by both
    // play-services-location and firebase-auth's play-services-auth) declares a hard, non-range
    // dependency on androidx.fragment:fragment:1.1.0 — no other node in the graph requests a newer
    // version, so Gradle's default highest-wins resolution settles on that old 1.1.0 with nothing
    // to override it. A dependency constraint (not a direct `implementation`) is the right fix:
    // it bumps the resolved version without adding an unused API surface, since nothing in this
    // codebase calls into androidx.fragment itself. 1.8.9 is the latest stable release (Google
    // Maven maven-metadata.xml; 1.9.0 is still -alpha/-rc only as of this check).
    constraints {
        implementation("androidx.fragment:fragment:1.8.9") {
            because(
                "play-services-base:18.9.0 (transitive via play-services-location and " +
                    "firebase-auth) pins androidx.fragment:fragment:1.1.0, which fails " +
                    "androidx.activity's InvalidFragmentVersionForActivityResult lint check " +
                    "(requires >= 1.3.0) against MainActivity's registerForActivityResult usage."
            )
        }
    }

    implementation("androidx.core:core-ktx:1.19.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.activity:activity-compose:1.9.3")

    // A17: was pinned at 2025.09.01, but that pin was never honoured — maps-compose (below)
    // declares its own compose-bom and Gradle's highest-wins BOM resolution let it silently
    // override this one project-wide, since before A16 even bumped maps-compose. See the
    // maps-compose block below (search "A16 review round 1") for the full mechanism and the
    // measured before/after numbers. Re-pinning here at 2026.06.01 — the version already in
    // force per `gradle :app:dependencies --configuration debugRuntimeClasspath` (maps-compose
    // 8.4.0 itself declares `platform("androidx.compose:compose-bom:2026.06.01")`) — makes the
    // declaration match reality today: the compose-bom-managed core artifacts (ui/foundation/
    // animation/runtime) still land on 1.11.4, verified before/after on both debugRuntimeClasspath
    // and releaseRuntimeClasspath.
    //
    // A17 code review round 1 (Major, fixed): a plain `implementation(platform(...))` BOM import
    // is unenforced — it only contributes a candidate to Gradle's highest-wins resolution, it does
    // not clamp. Verified directly against the pre-fix commit: the stale 2025.09.01 pin resolved
    // silently to 2026.06.01 with `BUILD SUCCESSFUL` and no warning, which is the exact silent
    // override this task exists to fix. Re-pinning at today's resolved value (above) alone would
    // have repeated that same silent-override failure mode the next time any dependency asks for a
    // newer compose-bom. The `strictly` constraint below makes that loud instead: any node in the
    // graph demanding a compose-bom outside this exact version now fails resolution with an
    // explicit conflict, rather than quietly winning. Verified this actually enforces (not just
    // documents) by temporarily lowering the strictly value below what maps-compose demands and
    // confirming the build failed with a version-conflict error before restoring the value below,
    // which matches the platform() import above and therefore does not move any resolved version.
    constraints {
        implementation("androidx.compose:compose-bom") {
            version { strictly("2026.06.01") }
            because(
                "maps-compose declares its own compose-bom, and Gradle's highest-wins BOM " +
                    "resolution silently overrode the plain implementation(platform(...)) pin " +
                    "above before this constraint existed (A17). `strictly` turns a future " +
                    "conflicting compose-bom demand into a build failure instead of a silent " +
                    "version bump."
            )
        }
    }
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.8.5")

    // Periodic/foreground-service scheduling (specs/009-device-runtime.md §3).
    implementation("androidx.work:work-runtime-ktx:2.10.0")

    // A10 (specs/009 §2): durable fix-queue storage, replacing the A1 in-memory placeholder
    // (specs/003 §10.4) behind the unchanged FixQueueStore interface (queue/room/).
    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    ksp("androidx.room:room-compiler:2.8.4")

    // A10 (specs/009 §1): FusedLocationProviderClient-backed real fix capture (location/).
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Real Firebase Auth (specs/003 §7, H1) — FirebaseAuthProvider's only consumer.
    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
    implementation("com.google.firebase:firebase-auth")
    // A9 (specs/003 §9, specs/009-device-runtime.md §5): real FCM — RealPushTokenProvider +
    // FindlyMessagingService's only new dependency (the BOM above pins its version).
    implementation("com.google.firebase:firebase-messaging")
    // `Task<T>.await()` bridge so FirebaseAuthProvider/RealPushTokenProvider can be plain
    // suspend-based classes.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")

    // Networking (specs/003 §5): Retrofit + OkHttp + kotlinx.serialization, chosen over Ktor for
    // its mature Android ecosystem, suspend-fun support, and predictable Response<T> based
    // interface-per-endpoint testing story.
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")

    // A6 (specs/007-public-join-links.md §4/§7, specs/003-android-client.md §12.3): on-device QR
    // generation for the public join link. `core` is ZXing's plain-Java barcode encoder/decoder —
    // no network access, no Android-framework dependency of its own, so nothing here can leak the
    // join code to a third party (a networked QR-image service would be a spec violation); the
    // only new dependency this task adds (see ui/groups/GroupQrCodeGenerator.kt's doc for the full
    // justification, reviewed per docs/security-review-checklist.md §4).
    implementation("com.google.zxing:core:3.5.3")

    // A12/A16 (specs/003-android-client.md §12): the real Google Maps tile renderer behind the
    // MapRenderer seam (GoogleMapRenderer replaces PlaceholderMapRenderer at AppContainer's
    // composition root). Needs a Maps API key at runtime (the manifest's
    // com.google.android.geo.API_KEY meta-data, sourced from BuildConfig.MAPS_API_KEY above) —
    // an empty key (the default until H1 provisions a real one, docs/azure-setup.md) still
    // builds and runs fine, it just yields a tile-less grey map, same "degrade gracefully
    // without secrets" pattern every other H1-waived dependency in this codebase already uses.
    // maps-compose brings MarkerComposable, letting markers render the design-system
    // FindlyMapMarkerBubble instead of a default pin (design/findly-design-system/README.md).
    //
    // A16: unpinned from 7.0.0 to 8.4.0 (the current release as of this task; Maven Central's
    // maven-metadata.xml lists 8.0.0 through 8.4.0 in the 8.x line, 2026-01-27 to 2026-07-16, no
    // deprecations or removals of GoogleMap/MarkerComposable/rememberCameraPositionState/
    // rememberUpdatedMarkerState across that range per the upstream CHANGELOG.md). A12 had pinned
    // 7.0.0 on the belief that 8.0.0+ required compileSdk 37 via core-ktx 1.19.0; that was wrong
    // for 8.0.0 specifically (its POM resolves core-ktx:1.17.0, whose own AAR
    // aar-metadata.properties declares minCompileSdk=36) — but by 8.4.0 it has actually become
    // true again: 8.4.0's POM resolves core-ktx:1.19.0 (core-ktx crossed to minCompileSdk=37
    // starting at 1.19.0; 1.17.0/1.18.0, used by maps-compose up through 8.3.1, both stayed at
    // minCompileSdk=36 — verified directly from each core-ktx AAR's aar-metadata.properties, not
    // assumed from version numbers alone). That is moot here since A14 already raised this
    // project to compileSdk 37, but it is the accurate reason 8.4.0 specifically needs it, not
    // the disproved 8.0.0 claim the previous version of this comment carried. No explicit
    // play-services-maps override: 8.4.0 pulls it transitively (via maps-ktx:6.2.0) at 20.0.0, a
    // pairing its own maintainers publish and test together (maps-ktx:6.2.0's own POM depends on
    // play-services-maps:20.0.0); verified against the real resolved graph with
    // `gradle :app:dependencies --configuration debugRuntimeClasspath` rather than assumed from
    // the POMs alone (A12's own standard).
    //
    // A16 review round 1 (Major, fixed): this bump is not maps-only — maps-compose declares its
    // own compose-bom, and Gradle's highest-wins resolution elevates the *entire* app's Compose
    // toolkit to it, overriding the explicit `platform("androidx.compose:compose-bom:2025.09.01")`
    // pin below. That override predates A16: at 7.0.0 the pin was already being forced up to
    // compose-bom 2025.12.00 (androidx.compose.ui/foundation/animation/runtime all resolving
    // 1.10.0), verified directly by re-running `gradle :app:dependencies` against the pre-A16
    // build file. At 8.4.0 it goes further — compose-bom 2026.06.01, with those same artifacts
    // resolving 1.11.4 — verified the same way against this file as committed. Both numbers
    // independently re-confirmed, not copied from the review. Accepted as a conscious
    // consequence of this bump (every Compose screen in the app now compiles against 1.11.4, not
    // just the map screens); the pin's own silent-override behavior is a separate, pre-existing
    // issue tracked as its own follow-up task, not something A16 fixes.
    //
    // A17: the follow-up above landed. The compose-bom pin (above, search "implementation(platform")
    // is now re-pinned at 2026.06.01 — the version this maps-compose release actually forces —
    // and backed by a `strictly` constraint (same block) so a future conflicting demand fails the
    // build loudly instead of silently winning highest-wins resolution the way this one did.
    implementation("com.google.maps.android:maps-compose:8.4.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    // A11 code-review fix: real Room.Migration(1, 2) verification (FindlyDatabaseMigrationTest)
    // needs an actual SQLite engine to run against on plain JVM (no Robolectric/instrumentation,
    // specs/003-android-client.md §14) - Room's bundled driver (BundledSQLiteDriver) provides
    // exactly that: a real, file-backed SQLite database constructible from a plain JUnit test.
    // The plain `androidx.sqlite:sqlite-bundled` coordinate resolves to the Android-target variant
    // by default in this Android application module (its native library is built for Android
    // ABIs, e.g. arm64-v8a - unusable in the host JVM process `./gradlew test` actually runs in,
    // UnsatisfiedLinkError otherwise) - `sqlite-bundled-jvm` is the explicit desktop/host-JVM
    // artifact coordinate that ships a native library for this machine's own OS instead.
    testImplementation("androidx.sqlite:sqlite-bundled-jvm:2.6.2")
}
