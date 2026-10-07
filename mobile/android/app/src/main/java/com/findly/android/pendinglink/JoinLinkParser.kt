package com.findly.android.pendinglink

import com.findly.android.joincode.JoinCodeAlphabet
import com.findly.android.ui.groups.GroupJoinHttpsLinkParser
import com.findly.android.ui.invites.FamilyInviteHttpsLinkParser

/**
 * Single entry for every 007 join/invite link form: `https://{JOIN_LINK_HOST}/g#CODE`, `/f#CODE`,
 * `findly://group-join?code=`, `findly://family-join?code=`. Plain `String?` components (no
 * `android.net.Uri`) so it is JVM-testable. Codes go through the shared whitelist sanitizer; wrong
 * host/path/scheme is not a join link (007 section 4).
 */
object JoinLinkParser {
    private const val CUSTOM_SCHEME = "findly"
    private const val GROUP_HOST = "group-join"
    private const val FAMILY_HOST = "family-join"

    fun parse(
        scheme: String?,
        host: String?,
        path: String?,
        fragment: String?,
        codeQueryParam: String?,
        joinLinkHost: String,
    ): IncomingLink? {
        (GroupJoinHttpsLinkParser.parse(scheme, host, path, fragment, joinLinkHost)
            as? GroupJoinHttpsLinkParser.Result.Matched)?.let {
            return IncomingLink(PendingLinkKind.GroupJoin, it.sanitizedCode)
        }
        (FamilyInviteHttpsLinkParser.parse(scheme, host, path, fragment, joinLinkHost)
            as? FamilyInviteHttpsLinkParser.Result.Matched)?.let {
            return IncomingLink(PendingLinkKind.FamilyInvite, it.sanitizedCode)
        }
        if (scheme.equals(CUSTOM_SCHEME, ignoreCase = true)) {
            val kind = when {
                host.equals(GROUP_HOST, ignoreCase = true) -> PendingLinkKind.GroupJoin
                host.equals(FAMILY_HOST, ignoreCase = true) -> PendingLinkKind.FamilyInvite
                else -> return null
            }
            return IncomingLink(kind, codeQueryParam?.let(JoinCodeAlphabet::sanitize))
        }
        return null
    }
}
