package com.findly.android.auth

/**
 * RED-PHASE STUB (A52) — replaced in the green commit. Deliberately the naive behaviour (no
 * normalisation, no sign-out) so the tests that need the real thing fail by assertion.
 */
suspend fun AuthProvider.idTokenOrThrow(forceRefresh: Boolean = false): String? =
    currentIdToken(forceRefresh)
