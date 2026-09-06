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
    fun wasDemoted(priority: Int, originalPriority: Int): Boolean = priority != originalPriority
}
