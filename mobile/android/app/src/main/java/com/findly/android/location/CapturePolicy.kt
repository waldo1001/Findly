package com.findly.android.location

/**
 * Pure age arithmetic behind specs/009-device-runtime.md §1.1 "Accepting a recent cached
 * position" — kept out of [FusedLocationCapturer] (thin, untested Play-services glue by design)
 * so this decision is unit-tested without a Play-services/Android-framework dependency.
 */
object CapturePolicy {

    /**
     * The `CurrentLocationRequest.setMaxUpdateAgeMillis` value for the *primary* one-shot
     * request: a fixed 2 minutes for `BALANCED` (`periodic`/`geofence`) — "the platform's most
     * recent already-computed location when it is ≤ 2 minutes old" may satisfy the request
     * outright. `HIGH` (`locate`/`manual`) gets `0`: those sources "exist to produce a fresh fix"
     * and MUST NOT accept an already-computed position.
     */
    fun maxUpdateAgeMillisFor(accuracy: LocationAccuracyTier): Long = when (accuracy) {
        LocationAccuracyTier.BALANCED -> BALANCED_MAX_UPDATE_AGE_MILLIS
        LocationAccuracyTier.HIGH -> 0L
    }

    /**
     * Whether a `lastLocation` fallback of age [cachedAgeMillis] may be queued after the primary
     * one-shot request came back `null`. `HIGH` (`locate`/`manual`) MUST NOT use either shortcut
     * — this is only ever `true` for `BALANCED`, and only when [cachedAgeMillis] is no older than
     * [maxCachedAgeMillis] (the caller's current `syncIntervalMinutes`, converted to millis — "a
     * slightly old position on cadence is worth more to the family than a silent gap", §1.1). A
     * negative age (clock skew) is rejected, not accepted.
     */
    fun acceptsCachedFallback(
        accuracy: LocationAccuracyTier,
        cachedAgeMillis: Long,
        maxCachedAgeMillis: Long,
    ): Boolean =
        accuracy == LocationAccuracyTier.BALANCED && cachedAgeMillis in 0..maxCachedAgeMillis

    private const val BALANCED_MAX_UPDATE_AGE_MILLIS = 120_000L
}
