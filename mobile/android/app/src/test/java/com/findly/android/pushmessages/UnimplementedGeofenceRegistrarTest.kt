package com.findly.android.pushmessages

import org.junit.Test

/** [UnimplementedGeofenceRegistrar] is A9's placeholder wiring target until A11 lands the real
 * `GeofencingClient`-backed [GeofenceRegistrar] (specs/009-device-runtime.md §6.2) — locks its
 * "safe no-op" contract. */
class UnimplementedGeofenceRegistrarTest {

    @Test
    fun `registerAll is a safe no-op`() {
        UnimplementedGeofenceRegistrar.registerAll(emptyList(), "\"1\"")
        // No exception thrown - that is the entire contract of this placeholder.
    }
}
