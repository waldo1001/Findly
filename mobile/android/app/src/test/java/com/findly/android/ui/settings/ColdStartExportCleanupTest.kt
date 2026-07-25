package com.findly.android.ui.settings

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [ColdStartExportCleanup] backs specs/008-privacy-endpoints.md §3.1 rule 2 (amended)'s cold-start
 * trigger: an export artifact must never survive a process restart. Screen-teardown and
 * share-sheet-return signals are forbidden as cleanup triggers (they can race a lazily-reading
 * share target), so a fresh process start — which by definition cannot be racing anything from a
 * previous process — is one of only two triggers left (the other being the account-deletion
 * wipe). Pure Kotlin (delegates to the injected [ExportArtifactCleaner], no `android.*`) so it's
 * unit-testable without a `Context`; `AppContainer`'s `init` block is the only call site, running
 * exactly once per process via `FindlyApplication.onCreate`.
 */
class ColdStartExportCleanupTest {

    @Test
    fun `run clears any export artifact left behind by a previous process`() {
        var clearCallCount = 0
        val cleanup = ColdStartExportCleanup(ExportArtifactCleaner { clearCallCount++ })

        cleanup.run()

        assertEquals(1, clearCallCount)
    }
}
