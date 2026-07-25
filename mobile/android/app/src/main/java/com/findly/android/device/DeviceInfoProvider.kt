package com.findly.android.device

/**
 * Supplies the required 001-api-contract.md §4.1 device-identity fields. Real implementation:
 * [AndroidDeviceInfoProvider] (`Build.MODEL` / `BuildConfig.VERSION_NAME`). Test fake:
 * `FakeDeviceInfoProvider` (`app/src/test/.../fakes/`).
 */
interface DeviceInfoProvider {
    val platform: String
    val model: String
    val appVersion: String
}
