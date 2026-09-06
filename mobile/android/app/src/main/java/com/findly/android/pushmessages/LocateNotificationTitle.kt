package com.findly.android.pushmessages

/**
 * 001-api-contract.md §8.1's normative title template, rendered on-device from
 * `data.requestedByName` — the Android `LOCATE_REQUEST` message is data-only on purpose (specs/009
 * §5.1), so the client (here: [com.findly.android.queue.worker.LocateForegroundService]'s own
 * foreground notification) builds this string itself rather than receiving it server-composed the
 * way iOS does in `aps.alert.title`.
 */
object LocateNotificationTitle {
    fun forRequester(requestedByName: String): String = "$requestedByName is locating you"
}
