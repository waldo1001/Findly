package com.findly.android.fakes

import com.findly.android.ui.settings.LocalStateWiper

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). */
class FakeLocalStateWiper : LocalStateWiper {
    val wipeAllCalls = mutableListOf<String>()

    override suspend fun wipeAll(uid: String) {
        wipeAllCalls.add(uid)
    }
}
