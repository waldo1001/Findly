package com.findly.android.ui.groups

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter

/**
 * On-device QR generation for the [GroupJoinLinkBuilder]-built public join link (specs/007-public-
 * join-links.md §4/§7, specs/003-android-client.md §12.3). ZXing's **`core`** artifact
 * (`com.google.zxing:core`) is the one new dependency this task (A6) adds — a pure-Java barcode
 * encoder/decoder with **zero network access and zero Android-framework dependency of its own**.
 * Chosen deliberately over `zxing-android-embedded`/Play-Services barcode-scanning APIs — both are
 * scanner-oriented and heavier, and the latter is Google-Play-Services-coupled — because
 * generation here needs only the plain encoder half, offline, with the smallest possible
 * dependency surface to security-review (docs/security-review-checklist.md §4). Using a networked
 * QR-image service instead would leak the join code — a bearer capability, specs/001-api-
 * contract.md §12.6 — to a third party; 007 §4 calls on-device generation a hard requirement, not
 * a style choice.
 */
object GroupQrCodeGenerator {

    /** Requested QR bitmap edge length in pixels — an internal raster-rendering parameter, not a
     * `FindlyTheme` design token (specs/003 §4.1's token vocabulary governs Compose styling
     * constants; this is the resolution of a generated bitmap, an unrelated concern). The
     * Composable call site scales the resulting image to fill its layout box (`Modifier
     * .fillMaxWidth().aspectRatio(1f)`), so this is a "render at least this crisp" floor, not a
     * fixed on-screen size. */
    const val DEFAULT_SIZE_PX = 512

    /**
     * Pure: encodes [content] (the exact [GroupJoinLinkBuilder] link — never re-derived here) into
     * a QR [BitMatrix] at [size]x[size] modules. [QRCodeWriter.encode] is synchronous, offline,
     * pure-Java — no I/O of any kind, let alone network — so this function is plain-JVM unit
     * testable (specs/003 §14) despite living in an Android module; the test checklist item "no
     * network call in the QR path" (007 §7) is asserted by this function's very shape: it has no
     * suspend-ability, no `Context`, no networking type anywhere in its signature or ZXing's own
     * dependency graph.
     */
    fun encodeQrMatrix(content: String, size: Int = DEFAULT_SIZE_PX): BitMatrix =
        QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)

    /**
     * Android-framework conversion of [encodeQrMatrix]'s pure output into a renderable [Bitmap] —
     * black modules on a white background (the QR standard's own polarity, required for scanner
     * compatibility, not a `FindlyTheme` color choice — hence using [android.graphics.Color]
     * directly here rather than a Compose theme token). Not unit-tested: [Bitmap] is a real
     * Android framework class unavailable in this project's plain-JUnit/no-Robolectric test setup
     * (specs/003 §14) — reviewed statically instead, consistent with this project's established
     * convention for framework-only rendering code (e.g. `PlaceholderMapRenderer`).
     */
    fun toBitmap(content: String, size: Int = DEFAULT_SIZE_PX): Bitmap {
        val matrix = encodeQrMatrix(content, size)
        val bitmap = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.RGB_565)
        for (x in 0 until matrix.width) {
            for (y in 0 until matrix.height) {
                bitmap.setPixel(x, y, if (matrix.get(x, y)) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }
}
