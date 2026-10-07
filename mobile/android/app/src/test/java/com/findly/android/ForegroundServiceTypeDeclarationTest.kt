package com.findly.android

import java.io.File
import javax.xml.XMLConstants
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
 * file a change would land in. **What it cannot see:** a dependency bump whose library manifest
 * merges in a type permission. None does as of A50 (the merged release manifest was checked), but
 * nothing re-checks it on a bump; that regression would show up as the Play commit failing again,
 * the way H13 did. The fix there is a `tools:node="remove"` entry, which this guard accepts. That
 * the type a worker passes to `ForegroundInfo` is declared on the service is `lintVitalRelease`'s
 * `SpecifyForegroundServiceType` check, not this test's.
 */
class ForegroundServiceTypeDeclarationTest {

    private val manifest: Document = parseManifest()

    @Test
    fun `the only foreground-service type permission is FOREGROUND_SERVICE_LOCATION`() {
        assertEquals(
            PLAY_DECLARATION_REASON,
            setOf("android.permission.FOREGROUND_SERVICE_LOCATION"),
            typePermissions(manifest),
        )
    }

    @Test
    fun `every service declares only the location foreground-service type`() {
        assertEquals(PLAY_DECLARATION_REASON, setOf("location"), serviceTypes(manifest))
    }

    // The two tests below pin the guard's own reading of the manifest against fixtures, because
    // the real manifest exercises neither case today.

    @Test
    fun `a type permission stripped with tools node remove is not counted as declared`() {
        // The standard way to strip a type permission a dependency merges in - the most likely
        // shape of the correct fix if this regression ever comes back through a library.
        val fixture = parse(
            """
            <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                xmlns:tools="http://schemas.android.com/tools">
                <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
                <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" tools:node="remove" />
                <application>
                    <service android:name=".A" android:foregroundServiceType="location" />
                    <service android:name=".B" android:foregroundServiceType="dataSync" tools:node="remove" />
                </application>
            </manifest>
            """,
        )

        assertEquals(setOf("android.permission.FOREGROUND_SERVICE_LOCATION"), typePermissions(fixture))
        assertEquals(setOf("location"), serviceTypes(fixture))
    }

    @Test
    fun `a type permission declared through uses-permission-sdk-23 is counted`() {
        val fixture = parse(
            """
            <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
                <uses-permission-sdk-23 android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
            </manifest>
            """,
        )

        assertEquals(
            setOf(
                "android.permission.FOREGROUND_SERVICE_LOCATION",
                "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
            ),
            typePermissions(fixture),
        )
    }

    private fun typePermissions(document: Document): Set<String> =
        (elements(document, "uses-permission") + elements(document, "uses-permission-sdk-23"))
            .map { it.getAttribute("android:name") }
            .filter { it.startsWith(TYPE_PERMISSION_PREFIX) }
            .toSet()

    private fun serviceTypes(document: Document): Set<String> =
        elements(document, "service")
            .map { it.getAttribute("android:foregroundServiceType") }
            .filter { it.isNotEmpty() }
            .flatMap { it.split('|') }
            .toSet()

    // An element marked tools:node="remove" is stripped by the manifest merger, so it is not
    // declared. The parser is not namespace-aware, so attributes are read by qualified name.
    private fun elements(document: Document, tag: String): List<Element> {
        val nodes = document.getElementsByTagName(tag)
        return (0 until nodes.length)
            .map { nodes.item(it) as Element }
            .filterNot { it.getAttribute("tools:node") == "remove" }
    }

    private fun parse(xml: String): Document = documentBuilder().parse(xml.trimIndent().byteInputStream())

    private fun documentBuilder() =
        DocumentBuilderFactory.newInstance()
            .apply { setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true) }
            .newDocumentBuilder()

    private fun parseManifest(): Document {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            val file = File(dir, "src/main/AndroidManifest.xml")
            if (file.isFile) return documentBuilder().parse(file)
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
