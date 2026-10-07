package com.findly.android

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

/**
 * A62 hardening (specs/010 section 1.3): the pending join/invite link lives in the app-private
 * `findly_pending_link` SharedPreferences file, and `allowBackup` is on, so both backup rule files
 * MUST exclude it — a 1 h capability code must never enter a cloud backup or a device transfer.
 * Reads the real `src/main/res/xml` files (the place a change would land).
 */
class BackupExclusionStructureTest {

    private fun xml(name: String): Element {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "src/main/res/xml/$name").isFile) dir = dir.parentFile
        val file = File(requireNotNull(dir) { "src/main/res/xml/$name not found" }, "src/main/res/xml/$name")
        return DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement
    }

    private fun sharedPrefExcludes(parent: Element): List<String> {
        val nodes = parent.getElementsByTagName("exclude")
        return (0 until nodes.length).map { nodes.item(it) as Element }
            .filter { it.getAttribute("domain") == "sharedpref" }
            .map { it.getAttribute("path") }
    }

    private val expected = listOf("findly_pending_link.xml")

    @Test
    fun `full-backup rules exclude the pending link file`() {
        assertEquals(expected, sharedPrefExcludes(xml("backup_rules.xml")))
    }

    @Test
    fun `data extraction rules exclude it from both cloud backup and device transfer`() {
        val root = xml("data_extraction_rules.xml")
        for (section in listOf("cloud-backup", "device-transfer")) {
            val nodes = root.getElementsByTagName(section)
            assertEquals("$section section present", 1, nodes.length)
            assertEquals(section, expected, sharedPrefExcludes(nodes.item(0) as Element))
        }
    }
}
