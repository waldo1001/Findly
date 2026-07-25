package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [GroupQrCodeGenerator.encodeQrMatrix] is the only part of the QR path this project's plain-JUnit
 * setup can exercise (specs/003-android-client.md §14) — [GroupQrCodeGenerator.toBitmap]'s
 * [android.graphics.Bitmap] conversion needs a real Android runtime. ZXing's `QRCodeWriter` is a
 * pure, offline, synchronous encoder (`com.google.zxing:core` — no network/Android dependency of
 * its own), so these tests are real proof the encode path works and genuinely encodes its input,
 * not a networked or hand-mocked stub (specs/007-public-join-links.md §7's "no network call in the
 * QR path" checklist item).
 */
class GroupQrCodeGeneratorTest {

    @Test
    fun `encodes at exactly the requested module size`() {
        val link = GroupJoinLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ")
        val matrix = GroupQrCodeGenerator.encodeQrMatrix(link, size = 200)
        assertEquals(200, matrix.width)
        assertEquals(200, matrix.height)
    }

    @Test
    fun `produces a real, non-degenerate matrix (both dark and light modules present)`() {
        val link = GroupJoinLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ")
        val matrix = GroupQrCodeGenerator.encodeQrMatrix(link, size = 200)
        var sawDark = false
        var sawLight = false
        for (x in 0 until matrix.width) {
            for (y in 0 until matrix.height) {
                if (matrix.get(x, y)) sawDark = true else sawLight = true
            }
        }
        assertTrue("expected at least one dark module", sawDark)
        assertTrue("expected at least one light module", sawLight)
    }

    @Test
    fun `different link content encodes to a different matrix`() {
        val matrixA = GroupQrCodeGenerator.encodeQrMatrix(
            GroupJoinLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ"),
            size = 100,
        )
        val matrixB = GroupQrCodeGenerator.encodeQrMatrix(
            GroupJoinLinkBuilder.buildHttpsLink("findly-join.example.net", "AAAAAAAA"),
            size = 100,
        )
        var identical = true
        for (x in 0 until matrixA.width) {
            for (y in 0 until matrixA.height) {
                if (matrixA.get(x, y) != matrixB.get(x, y)) identical = false
            }
        }
        assertTrue("different join codes must not encode to an identical QR matrix", !identical)
    }

    @Test
    fun `default size constant matches the module count used when size is omitted`() {
        val link = GroupJoinLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ")
        val matrix = GroupQrCodeGenerator.encodeQrMatrix(link)
        assertEquals(GroupQrCodeGenerator.DEFAULT_SIZE_PX, matrix.width)
        assertEquals(GroupQrCodeGenerator.DEFAULT_SIZE_PX, matrix.height)
    }
}
