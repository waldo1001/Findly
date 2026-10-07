// Top-level build file: plugin versions are declared once here (with apply false) so a future
// second module (specs/003-android-client.md still plans single-module for A1) applies them
// without repeating — and can't drift out of sync — a version.
//
// H1 CI note (2026-07-20): AGP 9.0+ has built-in Kotlin support and the standalone
// `org.jetbrains.kotlin.android` plugin is no longer applied (it errors: "the
// 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support since AGP
// 9.0" — kotl.in/gradle/agp-built-in-kotlin). The Compose/serialization Kotlin compiler
// sub-plugins are unaffected and still applied the same way.
plugins {
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.20" apply false
    // H1 (specs/003 §13): reads app/google-services.json to configure the real Firebase project.
    id("com.google.gms.google-services") version "4.5.0" apply false
    // A10 (specs/009-device-runtime.md §2): Room's annotation processor, for the durable
    // fix-queue (queue/room/). KSP2 is NOT version-paired with the Kotlin sub-plugins above:
    // Dependabot #18/#14 moved those to 2.4.20 (2026-10-07) while no 2.4.x KSP line exists on
    // Maven Central (newest 2.3.12). KSP 2.3.10's release notes carry a fix specifically for
    // Kotlin 2.4.0, and CI's `./gradlew test` + `assembleRelease` ran `:app:kspDebugKotlin` clean
    // against 2.4.20. Dependabot bumps this line on its own schedule.
    id("com.google.devtools.ksp") version "2.3.10" apply false
}
