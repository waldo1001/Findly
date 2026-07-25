package com.findly.android.network

import kotlinx.serialization.json.Json

/**
 * Shared [Json] configuration.
 *
 * `ignoreUnknownKeys = true` — 001-api-contract.md §1.1: "Clients MUST ignore unknown response
 * fields" (forward compatibility).
 *
 * `encodeDefaults` is deliberately left at its default (`false`): an optional request field left
 * at its `null` default is omitted from the outgoing JSON entirely, never sent as an explicit
 * `"field": null`. This is what makes 001 §4.1's "omitted token fields are left unchanged" pin
 * hold for [com.findly.android.network.dto.RegisterDeviceRequestDto]'s `pushToken` /
 * `locationPushToken`.
 */
val FindlyJson = Json {
    ignoreUnknownKeys = true
}
