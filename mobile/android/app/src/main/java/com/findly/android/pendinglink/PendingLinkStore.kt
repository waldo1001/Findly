package com.findly.android.pendinglink

import android.content.Context
import android.content.SharedPreferences
import com.findly.android.joincode.JoinCodeAlphabet
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** App-private durable backing of the pending-link slot (specs/010 section 1.3 "Persistence"). */
interface PendingLinkPersistence {
    fun read(): PendingLink?
    fun write(link: PendingLink)
    fun clear()
}

class InMemoryPendingLinkPersistence : PendingLinkPersistence {
    private var stored: PendingLink? = null
    override fun read() = stored
    override fun write(link: PendingLink) { stored = link }
    override fun clear() { stored = null }
}

/**
 * Plain `SharedPreferences` file `findly_pending_link` (010 section 1.3: app-private storage is
 * adequate; the value MUST NOT be logged). Malformed content reads as an empty slot.
 */
class SharedPreferencesPendingLinkPersistence(private val prefs: SharedPreferences) : PendingLinkPersistence {

    constructor(context: Context) : this(context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE))

    override fun read(): PendingLink? {
        val kind = when (prefs.getString(KEY_KIND, null)) {
            KIND_FAMILY -> PendingLinkKind.FamilyInvite
            KIND_GROUP -> PendingLinkKind.GroupJoin
            else -> return null
        }
        val code = prefs.getString(KEY_CODE, null)?.let(JoinCodeAlphabet::sanitize) ?: return null
        if (!prefs.contains(KEY_RECEIVED_AT)) return null
        return PendingLink(kind, code, prefs.getLong(KEY_RECEIVED_AT, 0L))
    }

    override fun write(link: PendingLink) {
        prefs.edit()
            .putString(KEY_KIND, if (link.kind == PendingLinkKind.FamilyInvite) KIND_FAMILY else KIND_GROUP)
            .putString(KEY_CODE, link.code)
            .putLong(KEY_RECEIVED_AT, link.receivedAt)
            .apply()
    }

    override fun clear() {
        prefs.edit().remove(KEY_KIND).remove(KEY_CODE).remove(KEY_RECEIVED_AT).apply()
    }

    companion object {
        const val FILE_NAME = "findly_pending_link"
        private const val KEY_KIND = "kind"
        private const val KEY_CODE = "code"
        private const val KEY_RECEIVED_AT = "receivedAt"
        private const val KIND_FAMILY = "familyInvite"
        private const val KIND_GROUP = "groupJoin"
    }
}

/** The one-slot store: memory (observable) in front of [PendingLinkPersistence]. */
class PendingLinkStore(private val persistence: PendingLinkPersistence) {
    private val _current = MutableStateFlow(persistence.read())
    val current: StateFlow<PendingLink?> = _current.asStateFlow()

    fun save(link: PendingLink) {
        persistence.write(link)
        _current.value = link
    }

    fun clear() {
        persistence.clear()
        _current.value = null
    }
}
