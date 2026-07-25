package com.findly.android.network

import com.findly.android.network.dto.FeaturesDto

/**
 * The client-side domain model of 001-api-contract.md §9's `features` object. Every limit
 * check anywhere in the app MUST read this (or the `limits`/`flags` nested inside it) — never a
 * hardcoded literal — mirroring the backend's own `PLAN_MATRIX`-only rule (backend/README.md,
 * 001 §9, §11).
 */
data class Features(
    val subscriptionStatus: String,
    val limits: PlanLimits,
    val flags: PlanFlags,
)

data class PlanLimits(
    val maxDevices: Int,
    val maxGeofences: Int,
    val historyDays: Int,
    val minSyncIntervalMinutes: Int,
    val locateRequestsPerDay: Int,
    val maxActiveGroups: Int? = null,
    val maxGroupMembers: Int? = null,
    val maxGroupDurationDays: Int? = null,
    val groupGraceDays: Int? = null,
)

data class PlanFlags(
    val pushToLocate: Boolean,
    val geofencing: Boolean,
    val historyReplay: Boolean,
    val groups: Boolean = false,
)

fun FeaturesDto.toDomain(): Features = Features(
    subscriptionStatus = subscriptionStatus,
    limits = PlanLimits(
        maxDevices = limits.maxDevices,
        maxGeofences = limits.maxGeofences,
        historyDays = limits.historyDays,
        minSyncIntervalMinutes = limits.minSyncIntervalMinutes,
        locateRequestsPerDay = limits.locateRequestsPerDay,
        maxActiveGroups = limits.maxActiveGroups,
        maxGroupMembers = limits.maxGroupMembers,
        maxGroupDurationDays = limits.maxGroupDurationDays,
        groupGraceDays = limits.groupGraceDays,
    ),
    flags = PlanFlags(
        pushToLocate = flags.pushToLocate,
        geofencing = flags.geofencing,
        historyReplay = flags.historyReplay,
        groups = flags.groups,
    ),
)
