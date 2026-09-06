package com.findly.android.pushmessages

/**
 * specs/009-device-runtime.md §5.1: comparing `RemoteMessage.getPriority()` with
 * `getOriginalPriority()` reveals whether FCM demoted this app's high-priority messages — "the
 * single most useful field diagnostic for this whole batch." Deliberately takes plain ints
 * (rather than the Firebase SDK's `RemoteMessage`) so this stays a pure, unit-testable comparison;
 * the framework glue that calls it (`FindlyMessagingService`) logs only a running **count** when
 * this returns `true` — never the message itself (docs/security-review-checklist.md: no
 * coordinates, `deviceId`, tokens, or phone numbers in logs).
 */
object PushPriorityDemotion {
    /** FCM's own "not populated" sentinel (`RemoteMessage.PRIORITY_UNKNOWN`) — kept as a plain Int
     * here (not the Firebase constant) for the same pure-testability reason as the parameters
     * themselves. Nit fix (A39 review): PRIORITY_UNKNOWN on either side must never count as a
     * demotion — it means the SDK didn't populate that field, not that FCM downgraded the
     * message — counting it inflated the demotion diagnostic. */
    private const val PRIORITY_UNKNOWN = 0

    fun wasDemoted(priority: Int, originalPriority: Int): Boolean =
        priority != originalPriority && priority != PRIORITY_UNKNOWN && originalPriority != PRIORITY_UNKNOWN
}
