package com.findly.android.applock

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** App-private durable backing of the app-lock setting and background timestamp
 * (specs/010 section 1.4: local per install, never sent to the server). */
interface AppLockPersistence {
    fun readEnabled(): Boolean
    fun writeEnabled(enabled: Boolean)
    fun readBackgroundedAt(): Long?
    fun writeBackgroundedAt(at: Long)
    fun clearBackgroundedAt()
    fun clear()
}

class InMemoryAppLockPersistence : AppLockPersistence {
    private var enabled = false
    private var backgroundedAt: Long? = null
    override fun readEnabled() = enabled
    override fun writeEnabled(enabled: Boolean) { this.enabled = enabled }
    override fun readBackgroundedAt() = backgroundedAt
    override fun writeBackgroundedAt(at: Long) { backgroundedAt = at }
    override fun clearBackgroundedAt() { backgroundedAt = null }
    override fun clear() { enabled = false; backgroundedAt = null }
}

/** Plain `SharedPreferences` file `findly_app_lock`; holds a boolean and a timestamp, no secrets. */
class SharedPreferencesAppLockPersistence(private val prefs: SharedPreferences) : AppLockPersistence {

    constructor(context: Context) : this(context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE))

    override fun readEnabled() = prefs.getBoolean(KEY_ENABLED, false)

    override fun writeEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    override fun readBackgroundedAt(): Long? =
        if (prefs.contains(KEY_BACKGROUNDED_AT)) prefs.getLong(KEY_BACKGROUNDED_AT, 0L) else null

    override fun writeBackgroundedAt(at: Long) {
        prefs.edit().putLong(KEY_BACKGROUNDED_AT, at).apply()
    }

    override fun clearBackgroundedAt() {
        prefs.edit().remove(KEY_BACKGROUNDED_AT).apply()
    }

    override fun clear() {
        prefs.edit().remove(KEY_ENABLED).remove(KEY_BACKGROUNDED_AT).apply()
    }

    companion object {
        const val FILE_NAME = "findly_app_lock"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_BACKGROUNDED_AT = "backgroundedAt"
    }
}

/** The setting and background timestamp: memory (observable) in front of [AppLockPersistence]. */
class AppLockStore(private val persistence: AppLockPersistence) {
    private val _enabled = MutableStateFlow(persistence.readEnabled())
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun setEnabled(value: Boolean) {
        persistence.writeEnabled(value)
        _enabled.value = value
    }

    fun backgroundedAt(): Long? = persistence.readBackgroundedAt()

    fun recordBackgrounded(at: Long) = persistence.writeBackgroundedAt(at)

    fun clearBackgrounded() = persistence.clearBackgroundedAt()

    /** End-of-session wipe (`LocalStateWiper.wipeAll`, specs/010 section 1.4). */
    fun clear() {
        persistence.clear()
        _enabled.value = false
    }
}
