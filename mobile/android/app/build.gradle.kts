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

// A49 (docs/implementation-handoff.md) — a signed release build MUST NOT ship a blank Maps key.
//
// The `mapsApiKey` default above is deliberately an empty string so local dev and PR builds never
// fail for a secret they don't need, and the comment there is right that the Maps SDK just renders
// a tile-less map when it is blank. What that reasoning missed is the consequence for a build that
// actually reaches Play: on 26 Aug 2026 this app was REJECTED under the Broken Functionality
// policy ("Unresponsive UI elements, such as buttons or icons"), and the evidence screenshot
// Google attached is the Family map rendering as a blank rectangle with only the zoom controls and
// the Google watermark on it — the exact appearance of a Maps SDK with no usable key. A silent
// empty string is a safe default for a build nobody ships and a release-stopping defect for one
// that is, so the default stays and this guard draws the line between the two.
//
// Gated on `hasReleaseSigningMaterial` (the same signal the release signingConfig uses) so it can
// only ever fire for a genuinely uploadable artifact, and registered on the task graph rather than
// thrown at configuration time so `test`/`assembleDebug` are unaffected even in CI, where the
// signing secrets are present on the job.
gradle.taskGraph.whenReady {
    val packagesSignedRelease = allTasks.any { task ->
        task.name == "assembleRelease" || task.name == "bundleRelease"
    }
    if (packagesSignedRelease && hasReleaseSigningMaterial && mapsApiKey.isBlank()) {
        throw GradleException(
            "MAPS_API_KEY is blank, but this is a signed release build that can be uploaded to " +
                "Play. Shipping it would render the map as a blank rectangle — the defect that got " +
                "this app rejected under the Broken Functionality policy on 26 Aug 2026. Pass " +
                "-PMAPS_API_KEY=<key> (CI: the MAPS_API_KEY repo secret, wired in " +
                ".github/workflows/android.yml). Unsigned local and PR release builds are " +
                "deliberately unaffected.",
        )
    }
}

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
        versionName = "1.4.0"
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
    // A63 (specs/010 section 1.4): MainActivity is now a FragmentActivity (androidx.biometric's
    // BiometricPrompt requires one), so androidx.fragment is used directly and declared directly.
    // History (A15, docs/store-readiness.md section 1): before A63 the app had no Fragment usage of
    // its own, and the dependency was only a constraint, because play-services-base (transitive via
    // play-services-location and firebase-auth) pins androidx.fragment:fragment:1.1.0, which fails
    // androidx.activity's InvalidFragmentVersionForActivityResult lint check (needs >= 1.3.0) against
    // MainActivity's registerForActivityResult usage. The direct dependency below still wins the
    // highest-version resolution over that 1.1.0 pin, so the lint check stays satisfied (verified by
    // lintDebug). 1.8.9 is the latest stable release (1.9.0 is still alpha/rc).
    implementation("androidx.fragment:fragment:1.9.1")

    // A63 (specs/010 section 1.4): BiometricPrompt with BIOMETRIC_WEAK or DEVICE_CREDENTIAL, the app
    // lock's authenticator. 1.1.0 is the latest *stable* release (1.2.x/1.4.x are alpha only as of
    // this check); Google Maven, no transitive network access. New dependency - security review
    // dependency audit.
    implementation("androidx.biometric:biometric:1.1.0")

    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Compose BOM (A17, corrected by A69). maps-compose declares its own compose-bom, so the BOM
    // this app resolves is whatever Gradle's highest-wins resolution picks among the app's own
    // platform(...) line below, the `strictly` constraint below, and maps-compose's request.
    // Since A17, a `strictly` constraint pins the BOM. What it really does (verified with
    // `./gradlew :app:dependencyInsight --configuration releaseRuntimeClasspath --dependency
    // androidx.compose:compose-bom`, both debug and release):
    //   - it FAILS the build when it conflicts with a first-level declaration, i.e. when the
    //     platform(...) line below names a different version than the strictly value;
    //   - it does NOT fail on a conflicting TRANSITIVE request: that request is silently
    //     downgraded to the strictly value (A69: maps-compose 9.0.1 asked for 2026.09.00 and got
    //     2026.06.01 with BUILD SUCCESSFUL, so maps-compose ran on an older Compose than it was
    //     built against).
    // The rule that follows: keep the strictly value and the platform(...) line EQUAL, and keep
    // both >= what maps-compose requires. Every compose-bom bump, including Dependabot's, must
    // change both lines in the same diff or android-build fails. After a maps-compose bump,
    // re-run the dependencyInsight command above: a `compose-bom:X -> Y` line with X different
    // from Y means the pin is below what maps-compose asks for and must be raised (the
    // `{strictly Y} -> Y` line is the pin itself and is fine).
    constraints {
        implementation("androidx.compose:compose-bom") {
            version { strictly("2026.09.00") }
            because(
                "Keep equal to the platform(...) line below and >= the compose-bom that " +
                    "maps-compose requires (A17, A69). strictly fails on a conflict with a " +
                    "first-level declaration but silently downgrades a transitive request, " +
                    "so the pin must never sit below what maps-compose asks for."
            )
        }
    }
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.10.2")

    // Periodic/foreground-service scheduling (specs/009-device-runtime.md §3).
    implementation("androidx.work:work-runtime-ktx:2.12.0")

    // A10 (specs/009 §2): durable fix-queue storage, replacing the A1 in-memory placeholder
    // (specs/003 §10.4) behind the unchanged FixQueueStore interface (queue/room/).
    implementation("androidx.room:room-runtime:2.8.5")
    implementation("androidx.room:room-ktx:2.8.5")
    ksp("androidx.room:room-compiler:2.8.5")

    // A10 (specs/009 §1): FusedLocationProviderClient-backed real fix capture (location/).
    implementation("com.google.android.gms:play-services-location:21.4.0")

    // Real Firebase Auth (specs/003 §7, H1) — FirebaseAuthProvider's only consumer.
    implementation(platform("com.google.firebase:firebase-bom:35.2.0"))
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
    implementation("com.squareup.retrofit2:retrofit:3.0.0")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    implementation("com.squareup.okhttp3:logging-interceptor:5.5.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")

    // A6 (specs/007-public-join-links.md §4/§7, specs/003-android-client.md §12.3): on-device QR
    // generation for the public join link. `core` is ZXing's plain-Java barcode encoder/decoder —
    // no network access, no Android-framework dependency of its own, so nothing here can leak the
    // join code to a third party (a networked QR-image service would be a spec violation); the
    // only new dependency this task adds (see ui/groups/GroupQrCodeGenerator.kt's doc for the full
    // justification, reviewed per docs/security-review-checklist.md §4).
    implementation("com.google.zxing:core:3.5.4")

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
    // A17/A69: the compose-bom pin above (search "implementation(platform") is kept at, or above,
    // the compose-bom this maps-compose release requires (2026.09.00 for 9.0.1, per its Gradle
    // module metadata). A `strictly` constraint silently downgrades a transitive request, so
    // the old 2026.06.01 pin made 9.0.1 run on an older Compose than it was built against
    // (A69); the pin now equals the request, so the downgrade is gone.
    //
    // 9.0.1 (Dependabot #28): 9.0.0's only breaking change swaps the transitive android-maps-ktx
    // for android-maps-utils; nothing in app/src imports maps-ktx directly.
    implementation("com.google.maps.android:maps-compose:9.0.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:5.5.1")
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
