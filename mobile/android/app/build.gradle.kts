// H1 CI note (2026-07-20): `org.jetbrains.kotlin.android` removed — AGP 9.0+ built-in Kotlin
// support makes it redundant (and a hard error to apply alongside it); see build.gradle.kts.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    // H1 (specs/003 §13): requires app/google-services.json (gitignored, real file supplied by
    // the user from the Firebase console) to be present at build time.
    id("com.google.gms.google-services")
}

// A2/A12 (specs/003-android-client.md §13, `ui/map/MapRenderer.kt`): the real map-tile SDK
// (A12's GoogleMapRenderer, com.google.maps.android:maps-compose below) needs a Google Maps API
// key that only exists once H1 (docs/azure-setup.md) provisions one. Read from a Gradle project
// property so it can be supplied via `-PMAPS_API_KEY=...` (CI secret) or a local, gitignored
// `local.properties`/`gradle.properties` override — NEVER hardcoded here and NEVER committed
// (docs/security-review-checklist.md §5). Empty string is the correct, safe default: the Maps
// SDK reads this (via the manifest meta-data below) at process start and simply renders a
// tile-less grey map when it's blank — no code branches on its presence.
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

android {
    namespace = "com.findly.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.findly.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
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
            isMinifyEnabled = false // TODO(H1): enable + tune proguard-rules.pro before shipping
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
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.activity:activity-compose:1.9.3")

    implementation(platform("androidx.compose:compose-bom:2025.09.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.8.5")

    // Offline fix-queue periodic worker scaffold (specs/003 §10.5) — no enqueue call sites wired yet.
    implementation("androidx.work:work-runtime-ktx:2.10.0")

    // Real Firebase Auth (specs/003 §7, H1) — FirebaseAuthProvider's only consumer.
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-auth")
    // A9 (specs/003 §9, specs/009-device-runtime.md §5): real FCM — RealPushTokenProvider +
    // FindlyMessagingService's only new dependency (the BOM above pins its version).
    implementation("com.google.firebase:firebase-messaging")
    // `Task<T>.await()` bridge so FirebaseAuthProvider/RealPushTokenProvider can be plain
    // suspend-based classes.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.1")

    // Networking (specs/003 §5): Retrofit + OkHttp + kotlinx.serialization, chosen over Ktor for
    // its mature Android ecosystem, suspend-fun support, and predictable Response<T> based
    // interface-per-endpoint testing story.
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")

    // A6 (specs/007-public-join-links.md §4/§7, specs/003-android-client.md §12.3): on-device QR
    // generation for the public join link. `core` is ZXing's plain-Java barcode encoder/decoder —
    // no network access, no Android-framework dependency of its own, so nothing here can leak the
    // join code to a third party (a networked QR-image service would be a spec violation); the
    // only new dependency this task adds (see ui/groups/GroupQrCodeGenerator.kt's doc for the full
    // justification, reviewed per docs/security-review-checklist.md §4).
    implementation("com.google.zxing:core:3.5.3")

    // A12 (specs/003-android-client.md §12): the real Google Maps tile renderer behind the
    // MapRenderer seam (GoogleMapRenderer replaces PlaceholderMapRenderer at AppContainer's
    // composition root). Needs a Maps API key at runtime (the manifest's
    // com.google.android.geo.API_KEY meta-data, sourced from BuildConfig.MAPS_API_KEY above) —
    // an empty key (the default until H1 provisions a real one, docs/azure-setup.md) still
    // builds and runs fine, it just yields a tile-less grey map, same "degrade gracefully
    // without secrets" pattern every other H1-waived dependency in this codebase already uses.
    // maps-compose brings MarkerComposable, letting markers render the design-system
    // FindlyMapMarkerBubble instead of a default pin (design/findly-design-system/README.md).
    // Pinned to 7.0.0, not the current 8.x line: 8.0.0+ transitively requires
    // androidx.core:core-ktx 1.19.0, whose AAR metadata demands compileSdk 37 — this project is
    // still on compileSdk 36 (only the android-36 platform is installed in this environment, and
    // bumping compileSdk/targetSdk is a separate, tracked decision outside A12's scope). 7.0.0 is
    // the newest release confirmed compileSdk-36-compatible (6.4.4 also works but is a year
    // older with no reason to prefer it over 7.0.0's upstream fixes). No explicit
    // play-services-maps override here — 7.0.0 pulls it transitively (via maps-ktx:5.2.1) at
    // 19.2.0, a pairing its own maintainers actually publish and test together; verified with
    // `gradle :app:dependencies` rather than assumed from the POM alone.
    implementation("com.google.maps.android:maps-compose:7.0.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.1")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
