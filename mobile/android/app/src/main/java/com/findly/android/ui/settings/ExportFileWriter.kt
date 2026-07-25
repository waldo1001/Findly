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
 * "Clients ... MUST offer export in settings and hand the file to the OS share/save sheet."
 * [PrivacyStateHolder] never touches `android.*` — it only produces the raw bytes; this object is
 * the one place they're written to disk and wrapped in a share [Intent].
 *
 * Writes into `cacheDir/exports/` (declared in `res/xml/file_paths.xml`, the only folder this
 * app's [FileProvider] authority exposes) rather than app-private storage, since the receiving
 * app (whatever the user picks in the chooser) needs a `content://` URI it can actually read from.
 */
object ExportFileWriter {

    /** Writes [result]'s body to a cache file and returns a chooser [Intent] ready to `startActivity`.
     * [fallbackFileName] is used when [ExportResult.suggestedFileName] is missing/unparsable. */
    fun buildShareIntent(
        context: Context,
        result: ExportResult,
        fallbackFileName: String = "findly-export.json",
    ): Intent {
        val exportsDir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(exportsDir, result.suggestedFileName?.takeIf { it.isNotBlank() } ?: fallbackFileName)
        file.writeBytes(result.body)

        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = result.contentType?.substringBefore(';')?.takeIf { it.isNotBlank() } ?: "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(sendIntent, "Save or share export")
    }
}
