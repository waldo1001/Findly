package com.findly.android

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Document
import org.w3c.dom.Element

/**
 * A50 regression guard (specs/003-android-client.md §11.6): the app declares exactly one
 * foreground-service type, `location`, and exactly one type permission,
 * `FOREGROUND_SERVICE_LOCATION`.
 *
 * Not a style rule. Google Play refuses to commit any release whose bundle carries a
 * `FOREGROUND_SERVICE_*` permission without a matching Play Console declaration, and the console
 * only offers that declaration once it has processed a bundle carrying the permission. A43 added
 * `FOREGROUND_SERVICE_DATA_SYNC` alongside a `dataSync` type on WorkManager's
 * `SystemForegroundService`, and from then on every publish failed at *Committing the Edit*
 * (handoff H13/H15) for a code path that never needed it: WorkManager promotes expedited work to a
 * foreground service only below API 31, the type permissions are enforced only from API 34.
 *
 * Reads the real `src/main/AndroidManifest.xml`, not the merged manifest, because this is the
 * file a change would land in. Library manifests have contributed no type permission so far; the
 * merged output is checked by hand when this guard changes (see the A50 dev-loop entry). That the
 * type a worker passes to `ForegroundInfo` is declared on the service is `lintVitalRelease`'s
 * `SpecifyForegroundServiceType` check, not this test's.
 */
class ForegroundServiceTypeDeclarationTest {

    private val manifest: Document = parseManifest()

    @Test
    fun `the only foreground-service type permission is FOREGROUND_SERVICE_LOCATION`() {
        val typePermissions = elements("uses-permission")
            .map { it.getAttribute("android:name") }
            .filter { it.startsWith(TYPE_PERMISSION_PREFIX) }
            .toSet()

        assertEquals(PLAY_DECLARATION_REASON, setOf("android.permission.FOREGROUND_SERVICE_LOCATION"), typePermissions)
    }

    @Test
    fun `every service declares only the location foreground-service type`() {
        val declaredTypes = elements("service")
            .map { it.getAttribute("android:foregroundServiceType") }
            .filter { it.isNotEmpty() }
            .flatMap { it.split('|') }
            .toSet()

        assertEquals(PLAY_DECLARATION_REASON, setOf("location"), declaredTypes)
    }

    private fun elements(tag: String): List<Element> {
        val nodes = manifest.getElementsByTagName(tag)
        return (0 until nodes.length).map { nodes.item(it) as Element }
    }

    private fun parseManifest(): Document {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            val file = File(dir, "src/main/AndroidManifest.xml")
            if (file.isFile) return DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
            dir = dir.parentFile
        }
        error(
            "Could not locate the android app module root (looked for src/main/AndroidManifest.xml " +
                "walking up from $cwd) — this test reads the real manifest, not a classpath resource.",
        )
    }

    private companion object {
        // The trailing underscore excludes the plain FOREGROUND_SERVICE permission, which every
        // foreground service needs and which carries no Play declaration of its own.
        const val TYPE_PERMISSION_PREFIX = "android.permission.FOREGROUND_SERVICE_"

        const val PLAY_DECLARATION_REASON =
            "A new foreground-service type blocks every Play publish until its Play Console " +
                "declaration exists, and the console cannot offer it before processing a bundle " +
                "that carries the permission (specs/003 §11.6, handoff H13/H15). Make that " +
                "declaration possible first, as its own change"
    }
}
