package com.findly.android.device

import android.os.Build
import com.findly.android.BuildConfig

/** Real, thin Android-framework [DeviceInfoProvider] — untested, like the backend's `src/adapters`
 * (backend/README.md's hexagonal split). */
class AndroidDeviceInfoProvider : DeviceInfoProvider {
    override val platform: String = "android"
    override val model: String = Build.MODEL
    override val appVersion: String = BuildConfig.VERSION_NAME
}
