package com.findly.android.ui.settings

import java.io.File

/**
 * Pure, JVM-only file operations for the on-disk export artifact (specs/008-privacy-endpoints.md
 * §3.1). Deliberately takes a plain [java.io.File] directory rather than an Android `Context` so
 * it's unit-testable with a real temp directory — no Robolectric/instrumented test needed. The
 * only `android.*`-touching piece of the export flow is [ExportFileWriter], which resolves
 * `context.cacheDir` and wraps the written [File] in a `content://` share [android.content.Intent].
 *
 * The on-disk filename is always [FILE_NAME] — **never** derived from server input. This single
 * choice satisfies two 008 §3.1 rules at once:
 * - Rule 3 ("no durable identifier in the on-disk name"): the server's own suggested filename
 *   literally embeds the subject's `userId` (001 §13.1: `findly-export-<userId>-<yyyy-MM-dd>.json`),
 *   so using it verbatim on disk would turn a cache-directory listing into a roster of exported
 *   family members.
 * - Rule 6 ("never build a path from a server-supplied filename"): `File(parent, child)` does not
 *   normalize `..`, so trusting the `Content-Disposition` header at all — even just for the
 *   filename — would let a compromised/buggy backend steer a write outside [exportsDir]. Ignoring
 *   the header for path purposes entirely is simpler and strictly safer than trying to sanitize it.
 */
object ExportArtifactStore {

    const val FILE_NAME = "export.json"

    /**
     * Deletes any previously-written export artifact under [exportsDir]. Called:
     * - before every new write ([write], below — 008 §3.1 rule 2: "defensively on the next export"),
     * - after the share/save handoff completes or is dismissed ([ExportFileWriter.clearArtifacts]),
     * - on screen teardown (`SettingsScreen.kt`'s `DisposableEffect`),
     * - and by the account-deletion local wipe ([DefaultLocalStateWiper]).
     *
     * Safe to call when [exportsDir] doesn't exist or is already empty.
     */
    fun clear(exportsDir: File) {
        if (exportsDir.exists()) {
            exportsDir.listFiles()?.forEach { it.delete() }
        }
    }

    /**
     * Writes [body] under [exportsDir] at the fixed, non-identifying [FILE_NAME], clearing any
     * prior artifact first (008 §3.1 rule 2 — an export artifact must never accumulate a second
     * copy). Returns the written [File].
     *
     * [suggestedName] is the raw, untrusted `Content-Disposition` hint ([ExportResult.suggestedFileName]
     * — display purposes only) — accepted here purely so [ExportFileWriter] has nowhere else to
     * route it into a path, closing off the temptation entirely rather than relying on every call
     * site remembering not to. It is **never read** below; a directory-traversal or absolute-path
     * value is exactly as harmless as a friendly one (008 §3.1 rule 6).
     */
    fun write(exportsDir: File, body: ByteArray, suggestedName: String? = null): File {
        clear(exportsDir)
        exportsDir.mkdirs()
        val file = File(exportsDir, FILE_NAME)
        file.writeBytes(body)
        return file
    }
}
