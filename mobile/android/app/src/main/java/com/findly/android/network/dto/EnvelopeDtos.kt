package com.findly.android.network.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/** The success envelope (001-api-contract.md §1.3): `{ "data": ..., "features": ... }`. Every
 * endpoint that has a body includes `features` — the two body-less exceptions (§3.6's bare 204,
 * §7.1's bare 304) never construct an [Envelope] at all (network/FindlyApiClient.kt handles those
 * as dedicated branches, see specs/003-android-client.md §6.3). */
@Serializable
data class Envelope<T>(
    val data: T,
    val features: FeaturesDto,
)

/** The error envelope (001-api-contract.md §1.3): `{ "error": { code, message, details?,
 * requestId } }`. */
@Serializable
data class ErrorEnvelope(
    val error: ApiErrorBody,
)

@Serializable
data class ApiErrorBody(
    val code: String,
    val message: String,
    val details: JsonObject? = null,
    val requestId: String,
)

/** 001-api-contract.md §9 — present in every success envelope. */
@Serializable
data class FeaturesDto(
    val subscriptionStatus: String,
    val limits: PlanLimitsDto,
    val flags: PlanFlagsDto,
)

/** `maxActiveGroups`/`maxGroupMembers`/`maxGroupDurationDays`/`groupGraceDays` are the
 * specs/005-temporary-groups.md additions to 001 §9 — defaulted to `null` so decoding still
 * succeeds against any envelope fixture predating groups (`ignoreUnknownKeys` handles the
 * reverse: an older client seeing these new fields for the first time). */
@Serializable
data class PlanLimitsDto(
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

@Serializable
data class PlanFlagsDto(
    val pushToLocate: Boolean,
    val geofencing: Boolean,
    val historyReplay: Boolean,
    val groups: Boolean = false,
)
