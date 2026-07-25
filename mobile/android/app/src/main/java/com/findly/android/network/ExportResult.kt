package com.findly.android.network

/**
 * The raw, unenveloped `GET /export` document (001-api-contract.md §13.1 — "the one **unenveloped**
 * response in the API"; specs/003-android-client.md §12.4). [FindlyApiClient] deliberately does
 * NOT parse [body] beyond the HTTP layer — it is handed to the OS share/save sheet exactly as
 * received.
 *
 * @property body the raw response bytes (the export JSON document, UTF-8).
 * @property suggestedFileName parsed from the `Content-Disposition` header (001 §13.1:
 *   `findly-export-<userId>-<yyyy-MM-dd>.json`); `null` if the header is missing or unparsable —
 *   callers MUST supply a fallback name in that case.
 * @property contentType the raw `Content-Type` response header (001 §13.1:
 *   `application/json; charset=utf-8`), `null` if absent.
 *
 * Note: the compiler-generated `equals`/`hashCode` compare [body] by array **reference**, not
 * content (a `ByteArray` property never gets structural equality from a plain `data class`). Tests
 * that need to assert on the export content compare `.body.decodeToString()`/`.body.size`
 * explicitly rather than `==` on the whole instance.
 */
data class ExportResult(
    val body: ByteArray,
    val suggestedFileName: String?,
    val contentType: String?,
)
