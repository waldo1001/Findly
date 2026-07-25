package com.findly.android.device

import java.util.UUID

/**
 * Returns a client-generated UUIDv4 `deviceId`, persisted per `uid` (001-api-contract.md §1.4:
 * "stable per app install and per signed-in user — clients MUST generate a fresh deviceId when
 * the signed-in user changes"). A fresh id is generated the first time a given `uid` is seen on
 * this install; never reused for a different uid.
 *
 * Pure Kotlin/JVM — testable with an in-memory [DeviceIdStore] fake and a deterministic
 * [idGenerator], no emulator required.
 */
class DeviceIdProvider(
    private val store: DeviceIdStore,
    private val idGenerator: () -> String = { UUID.randomUUID().toString() },
) {
    fun deviceIdFor(uid: String): String {
        store.get(uid)?.let { return it }
        val fresh = idGenerator()
        store.put(uid, fresh)
        return fresh
    }
}
