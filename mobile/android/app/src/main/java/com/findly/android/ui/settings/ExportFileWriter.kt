package com.findly.android.ui.settings

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.findly.android.network.ExportResult
import java.io.File

/**
 * Thin, untested Android-framework glue (same category as `AndroidDeviceInfoProvider`,
 * `SharedPreferencesDeviceIdStore` — specs/003-android-client.md §3) that hands an [ExportResult]
 * to the OS share sheet, per 001-api-contract.md §13.1 / specs/008-privacy-endpoints.md §3:
 * "Clients ... MUST offer export in settings and hand the file to the OS share/save sheet,
 * subject to §3.1." [PrivacyStateHolder] never touches `android.*` — it only produces the raw
 * bytes; this object is the one place they're written to disk and wrapped in a share [Intent].
 * All actual file placement/cleanup logic lives in the pure, unit-tested [ExportArtifactStore] —
 * this class only resolves `context.cacheDir` and builds Android framework types around it.
 *
 * Writes into `cacheDir/exports/` (declared in `res/xml/file_paths.xml`, the only folder this
 * app's [FileProvider] authority exposes — never `<root-path>`, per 008 §3.1 rule 4) rather than
 * external/shared storage, since the receiving app (whatever the user picks in the chooser) needs
 * a `content://` URI it can actually read from, via a temporary, revocable grant
 * ([Intent.FLAG_GRANT_READ_URI_PERMISSION]) — never a durable one.
 */
object ExportFileWriter {

    private const val EXPORTS_SUBDIR = "exports"

    /** Writes [result]'s body via [ExportArtifactStore] (always at the fixed, non-identifying
     * on-disk name — the server-supplied `Content-Disposition` filename in [result] is display
     * input only and is never used to build a path, 008 §3.1 rules 3/6) and returns a chooser
     * [Intent] ready to `startActivity`. Deliberately a plain `startActivity`, not an
     * `ActivityResultLauncher` — see [clearArtifacts]'s doc for why the chooser's result callback
     * is not a safe cleanup signal. */
    fun buildShareIntent(context: Context, result: ExportResult): Intent {
        val file = ExportArtifactStore.write(exportsDir(context), result.body, result.suggestedFileName)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = result.contentType?.substringBefore(';')?.takeIf { it.isNotBlank() } ?: "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(sendIntent, "Save or share export")
    }

    /**
     * Removes any export artifact (008 §3.1 rule 2, amended). Called from exactly two places —
     * both are triggers that cannot race a share-sheet consumer still reading the file:
     * - `AppContainer`'s cold-start wipe, so an artifact never survives a process restart;
     * - [DefaultLocalStateWiper], as part of the account-deletion local wipe.
     *
     * [buildShareIntent] itself also clears any prior artifact before writing a new one, so at
     * most one ever exists. Deliberately **not** called from `SettingsScreen.kt` on the share
     * chooser's return/dismissal or on screen teardown: an implicit `ACTION_SEND` chooser's
     * activity-result callback fires as soon as the target activity is *launched*, not once it
     * has finished reading the `content://` bytes — clearing on that signal would delete the file
     * out from under lazily-reading targets like "Save to Files"/"Save to Drive" and silently
     * break the export. Privacy that breaks the feature is a bug, not privacy (008 §3.1 rule 2).
     */
    fun clearArtifacts(context: Context) {
        ExportArtifactStore.clear(exportsDir(context))
    }

    private fun exportsDir(context: Context) = File(context.cacheDir, EXPORTS_SUBDIR)
}
