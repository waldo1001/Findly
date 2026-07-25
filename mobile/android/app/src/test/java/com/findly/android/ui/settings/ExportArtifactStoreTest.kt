package com.findly.android.ui.settings

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * [ExportArtifactStore] is pure `java.io.File` logic (no `android.*`) — testable with a real temp
 * directory, no Robolectric/instrumented test needed. Covers specs/008-privacy-endpoints.md §3.1's
 * export-artifact hygiene rules 2 (amended: cleared before every new write, so at most one
 * artifact ever exists — [ColdStartExportCleanupTest] and `LocalStateWiperTest` cover this rule's
 * other two non-racing triggers, cold start and account-deletion wipe), 3 (no durable identifier
 * in the on-disk name), and 6 (never build a path from server-supplied input — this store never
 * even looks at server input, it always writes the fixed [ExportArtifactStore.FILE_NAME]).
 */
class ExportArtifactStoreTest {

    private lateinit var exportsDir: File

    @Before
    fun setUp() {
        exportsDir = Files.createTempDirectory("export-artifact-test").toFile().resolve("exports")
    }

    @After
    fun tearDown() {
        exportsDir.parentFile?.deleteRecursively()
    }

    @Test
    fun `write creates the file at the fixed on-disk name, ignoring any server-supplied name`() {
        val file = ExportArtifactStore.write(exportsDir, "hello".toByteArray())

        assertEquals(ExportArtifactStore.FILE_NAME, file.name)
        assertEquals(exportsDir.canonicalFile, file.parentFile?.canonicalFile)
        assertArrayEquals("hello".toByteArray(), file.readBytes())
    }

    @Test
    fun `write never embeds a durable userId in the on-disk name, even when the server suggests one (008 §3_1 rule 3)`() {
        // The real 001 §13.1 shape: findly-export-<userId>-<yyyy-MM-dd>.json.
        val file = ExportArtifactStore.write(exportsDir, "{}".toByteArray(), "findly-export-uid-parent-2026-07-25.json")

        assertFalse("on-disk filename must not carry a subject identifier", file.name.contains("uid"))
        assertFalse(file.name.contains("u1"))
        assertEquals("export.json", file.name)
    }

    @Test
    fun `a path-traversal-shaped suggested filename can never escape the exports directory (008 §3_1 rule 6)`() {
        // Genuinely adversarial: the malicious name is fed into the real write() call — the same
        // call site ExportFileWriter.buildShareIntent uses, passing ExportResult.suggestedFileName
        // straight through. Proves write() ignores it rather than merely never being called with
        // it. A regression that resurrected the old `File(exportsDir, suggestedName ?: FILE_NAME)`
        // pattern would both escape the directory AND fail these assertions.
        val maliciousSuggestedName = "../../../evil.txt"

        val file = ExportArtifactStore.write(exportsDir, "payload".toByteArray(), maliciousSuggestedName)

        assertEquals(ExportArtifactStore.FILE_NAME, file.name)
        assertFalse(file.name.contains(".."))
        assertTrue(
            "written file must stay inside exportsDir",
            file.canonicalPath.startsWith(exportsDir.canonicalPath),
        )
    }

    @Test
    fun `an absolute-path suggested filename is also ignored (008 §3_1 rule 6)`() {
        val absoluteAttempt = "/etc/passwd"

        val file = ExportArtifactStore.write(exportsDir, "payload".toByteArray(), absoluteAttempt)

        assertEquals(ExportArtifactStore.FILE_NAME, file.name)
        assertTrue(file.canonicalPath.startsWith(exportsDir.canonicalPath))
    }

    @Test
    fun `write clears any prior artifact first - at most one file ever exists`() {
        ExportArtifactStore.write(exportsDir, "old".toByteArray())
        Files.write(exportsDir.resolve("stray-leftover.tmp").toPath(), "leftover".toByteArray())

        val file = ExportArtifactStore.write(exportsDir, "new".toByteArray())

        assertEquals(listOf(file.name), exportsDir.listFiles()?.map { it.name })
        assertArrayEquals("new".toByteArray(), file.readBytes())
    }

    @Test
    fun `clear removes every file in the exports directory`() {
        ExportArtifactStore.write(exportsDir, "data".toByteArray())
        assertTrue(exportsDir.listFiles()?.isNotEmpty() == true)

        ExportArtifactStore.clear(exportsDir)

        assertTrue(exportsDir.listFiles()?.isEmpty() != false)
    }

    @Test
    fun `clear on a directory that was never created is a harmless no-op`() {
        ExportArtifactStore.clear(exportsDir) // never written to — doesn't exist yet
    }
}
