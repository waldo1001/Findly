package com.findly.android.ui.devices

import com.findly.android.network.PlanLimits
import com.findly.android.ui.designsystem.components.FindlyDropdownOption

/**
 * The pure, presentation-only builder behind the §4.2 sync-interval [FindlyDropdownField]
 * (specs/010-app-shell-and-screen-ux.md §4.2/§9; specs/001-api-contract.md §1.4/§9). No Compose
 * import — plain Kotlin/JVM, unit-testable with plain JUnit (specs/003-android-client.md §14),
 * mirroring [com.findly.android.ui.designsystem.components.FindlyNavDrawerItems]'s "pure list
 * builder behind the component" shape.
 */
/**
 * The two 010 §4.2 groups the sync-interval dropdown sections its values under (amended
 * 2026-09-06, 000 §D19 — the low-power presence decision): [LIVE] is the four "live" intervals
 * (5-30 min, specs/009 §1.3) that keep a background presence running; [BATTERY_SAVER] is the
 * three opportunistic intervals (1 hour-1 day, §3.1) with no presence. [label]/[description] are
 * 010 §4.2's exact wording, reused verbatim for both the menu's section header and (via
 * [FindlyDropdownOption.groupLabel]) the closed field's `"15 min · Live"` suffix.
 */
enum class SyncIntervalGroup(val label: String, val description: String) {
    LIVE(
        "Live",
        "keeps Findly running in the background; on Android a persistent notification is shown",
    ),
    BATTERY_SAVER(
        "Battery saver",
        "reports when the phone wakes up; positions may be hours old",
    ),
}

object SyncIntervalOptions {
    /** The exact, closed 001 §1.4 value set, in the §4.2 presentation order. */
    val ALLOWED_MINUTES: List<Int> = listOf(5, 10, 15, 30, 60, 120, 1440)

    /** 010 §4.2's exact wording: "5 min, 10 min, 15 min, 30 min, 1 hour, 2 hours, 1 day". */
    fun labelFor(minutes: Int): String = when (minutes) {
        60 -> "1 hour"
        120 -> "2 hours"
        1440 -> "1 day"
        else -> "$minutes min"
    }

    /** specs/009 §1.3/§3: the four presence ("live") intervals vs. the three opportunistic
     * ("battery saver") ones — the exact same boundary [com.findly.android.queue.worker.SyncStrategySelector]
     * draws for the foreground-service-vs-WorkManager choice, restated here as the presentation
     * grouping rather than re-deriving it (this module doesn't depend on `queue.worker`). */
    fun groupFor(minutes: Int): SyncIntervalGroup =
        if (minutes <= 30) SyncIntervalGroup.LIVE else SyncIntervalGroup.BATTERY_SAVER

    /**
     * 010 §4.2/§9: values below [minSyncIntervalMinutes] — always the caller's own
     * `features.limits.minSyncIntervalMinutes`, never a hardcoded literal (`CLAUDE.md`'s
     * subscription-readiness rule) — render disabled with the limit named as the reason. The
     * server remains the sole source of truth for validation (010 §9); this is presentation only.
     */
    fun build(minSyncIntervalMinutes: Int): List<FindlyDropdownOption<Int>> = ALLOWED_MINUTES.map { minutes ->
        val enabled = minutes >= minSyncIntervalMinutes
        val group = groupFor(minutes)
        FindlyDropdownOption(
            value = minutes,
            label = labelFor(minutes),
            enabled = enabled,
            disabledReason = if (enabled) null else "Your plan's minimum interval is ${labelFor(minSyncIntervalMinutes)}",
            groupLabel = group.label,
            groupDescription = group.description,
        )
    }

    /**
     * The fail-closed wrapper around [build] for callers that only have a nullable
     * [PlanLimits] (specs/010-app-shell-and-screen-ux.md sec4.2/sec9; CLAUDE.md's subscription-
     * readiness rule -- limits come from `features`, never hardcoded at call sites, and a
     * fallback for a missing limit must fail closed, never open).
     *
     * [limits] is null only for specs/003-android-client.md sec6.2's two documented body-less
     * successes (sec3.6's bare 204, sec7.1's bare 304) -- `GET /devices` is a 200-with-body
     * endpoint, so this branch is spec-unreachable for a loaded `DevicesUiState.Content` today.
     * It still fails closed rather than defaulting the floor to 0: a floor of 0 would disable
     * *nothing*, silently granting every 001 sec1.4 value regardless of the caller's actual plan
     * -- exactly backwards for a subscription limit, and exactly the failure mode that becomes
     * live the moment this branch stops being unreachable (a future contract change, a backend
     * bug, a new caller).
     */
    fun buildForLimits(limits: PlanLimits?): List<FindlyDropdownOption<Int>> {
        val minSyncIntervalMinutes = limits?.minSyncIntervalMinutes
        if (minSyncIntervalMinutes != null) return build(minSyncIntervalMinutes)

        return ALLOWED_MINUTES.map { minutes ->
            val group = groupFor(minutes)
            FindlyDropdownOption(
                value = minutes,
                label = labelFor(minutes),
                enabled = false,
                disabledReason = "Couldn't confirm your plan's limits",
                groupLabel = group.label,
                groupDescription = group.description,
            )
        }
    }
}
