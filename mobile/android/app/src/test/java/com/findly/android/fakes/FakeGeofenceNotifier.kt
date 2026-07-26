package com.findly.android.fakes

import com.findly.android.pushmessages.GeofenceNotifier

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Records every
 * posted title for `GeofenceEventPushHandlerTest` (001-api-contract.md §8.2). */
class FakeGeofenceNotifier : GeofenceNotifier {
    val titles = mutableListOf<String>()

    override fun notify(title: String) {
        titles.add(title)
    }
}
