package com.findly.android.ui.devices

import com.findly.android.ui.designsystem.components.FindlyDropdownOption

/**
 * The pure, presentation-only builder behind the §4.2 sync-interval [FindlyDropdownField]
 * (specs/010-app-shell-and-screen-ux.md §4.2/§9; specs/001-api-contract.md §1.4/§9). No Compose
 * import — plain Kotlin/JVM, unit-testable with plain JUnit (specs/003-android-client.md §14),
 * mirroring [com.findly.android.ui.designsystem.components.FindlyNavDrawerItems]'s "pure list
 * builder behind the component" shape.
 *
 * STUB (deliberately wrong, not absent): returns an empty list so `SyncIntervalOptionsTest`'s
 * assertions fail on real content, not on a missing type — TDD red, about to be replaced.
 */
object SyncIntervalOptions {
    val ALLOWED_MINUTES: List<Int> = emptyList()

    fun labelFor(minutes: Int): String = ""

    fun build(minSyncIntervalMinutes: Int): List<FindlyDropdownOption<Int>> = emptyList()
}
