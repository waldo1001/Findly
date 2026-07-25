package com.findly.android.fakes

import com.findly.android.network.Features
import com.findly.android.network.PlanFlags
import com.findly.android.network.PlanLimits

/** Shared default [Features] fixture for A2 ViewModel tests (mirrors 001-api-contract.md §9's
 * example values) — avoids re-declaring the same plan-limits object in every fake/test.
 *
 * A5 addition (specs/005-temporary-groups.md §4): the four group-era limits plus `flags.groups`
 * default to `null`/`false` so every pre-A5 call site is unaffected; groups tests pass
 * `groupsFlag = true` (and the specific limits they need) explicitly. */
fun defaultFeatures(
    maxDevices: Int = 10,
    maxGeofences: Int = 20,
    historyDays: Int = 90,
    minSyncIntervalMinutes: Int = 5,
    locateRequestsPerDay: Int = 100,
    maxActiveGroups: Int? = null,
    maxGroupMembers: Int? = null,
    maxGroupDurationDays: Int? = null,
    groupGraceDays: Int? = null,
    groupsFlag: Boolean = false,
): Features = Features(
    subscriptionStatus = "free",
    limits = PlanLimits(
        maxDevices = maxDevices,
        maxGeofences = maxGeofences,
        historyDays = historyDays,
        minSyncIntervalMinutes = minSyncIntervalMinutes,
        locateRequestsPerDay = locateRequestsPerDay,
        maxActiveGroups = maxActiveGroups,
        maxGroupMembers = maxGroupMembers,
        maxGroupDurationDays = maxGroupDurationDays,
        groupGraceDays = groupGraceDays,
    ),
    flags = PlanFlags(pushToLocate = true, geofencing = true, historyReplay = true, groups = groupsFlag),
)

/** A5 convenience: the same fixture with the specs/005 §4 free-plan group limits populated and
 * `flags.groups = true` — the shape a groups-screen test normally wants. */
fun groupsFeatures(
    maxActiveGroups: Int = 5,
    maxGroupMembers: Int = 50,
    maxGroupDurationDays: Int = 30,
    groupGraceDays: Int = 7,
): Features = defaultFeatures(
    maxActiveGroups = maxActiveGroups,
    maxGroupMembers = maxGroupMembers,
    maxGroupDurationDays = maxGroupDurationDays,
    groupGraceDays = groupGraceDays,
    groupsFlag = true,
)
