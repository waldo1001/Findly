package com.findly.android.fakes

import android.content.SharedPreferences

/**
 * A plain-JVM `SharedPreferences` test double — code-review fix (A25 round 1, Minor 2): every
 * `SharedPreferences`-backed store in this module (`SharedPreferencesPermissionDisclosureStore`,
 * `SharedPreferencesDeviceIdStore`, `SharedPreferencesGeofenceConfigStateStore`, ...) previously had
 * zero direct coverage — only their in-memory test doubles were exercised, so a bug in the real
 * `SharedPreferences` wiring itself (wrong key, `commit()` vs `apply()`, `Editor` chaining) could
 * ship undetected.
 *
 * This module has no Robolectric and no `androidTest` source set (`app/build.gradle.kts`;
 * `WindowThemeDayNightTest`'s doc), so nothing here can exercise Android's *real*
 * `SharedPreferences` implementation. What this CAN do, and does: `android.content.SharedPreferences`
 * and `SharedPreferences.Editor` are plain interfaces — a from-scratch implementation backed by an
 * in-memory `MutableMap` satisfies them with **no Android runtime call at all**, so it needs no
 * stub-jar workaround. Constructing `SharedPreferencesPermissionDisclosureStore` (or any of the
 * other `SharedPreferences`-backed stores) against this fake and asserting through the *real*
 * production class — not a hand-rolled in-memory reimplementation of it — is a genuine, if partial,
 * step up from testing only `InMemoryPermissionDisclosureStore`: it exercises the actual key names
 * and the actual `getBoolean`/`putBoolean`/`remove`/`apply` calls the real class makes, and a second
 * store instance backed by the *same* `FakeSharedPreferences` is the closest a JVM unit test can
 * come to simulating "read back after a fresh process" without a real `Context`.
 *
 * Deliberately does not implement `commit()`'s return contract precisely (`commit()` here always
 * "succeeds") and ignores change listeners — no code under test in this module uses either.
 */
class FakeSharedPreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String?, defValue: String?): String? =
        values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        (values[key] as? Set<String>)?.toMutableSet() ?: defValues

    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = FakeEditor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    /**
     * Mutates the backing map directly on `apply()`/`commit()`, same as the real implementation's
     * eventual effect — pending edits are staged in [pending] until then, so a `getBoolean` call
     * mid-edit (before `apply`/`commit`) still sees the pre-edit value, matching real
     * `SharedPreferences.Editor` semantics.
     */
    private inner class FakeEditor : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val removals = mutableSetOf<String>()
        private var clearAll = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor =
            apply { key?.let { pending[it] = value } }

        override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor =
            apply { key?.let { pending[it] = values } }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor =
            apply { key?.let { pending[it] = value } }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor =
            apply { key?.let { pending[it] = value } }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor =
            apply { key?.let { pending[it] = value } }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor =
            apply { key?.let { pending[it] = value } }

        override fun remove(key: String?): SharedPreferences.Editor =
            apply { key?.let { removals += it } }

        override fun clear(): SharedPreferences.Editor = apply { clearAll = true }

        override fun commit(): Boolean {
            applyPending()
            return true
        }

        override fun apply() = applyPending()

        private fun applyPending() {
            if (clearAll) values.clear()
            removals.forEach { values.remove(it) }
            values.putAll(pending)
        }
    }
}
