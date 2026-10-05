package com.findly.android.auth

/**
 * RED-PHASE STUB (A52) — replaced in the green commit. Deliberately classifies everything as
 * transient so the tests that need `UserInvalid` fail by assertion.
 */
fun Throwable.toIdTokenException(): IdTokenException = IdTokenException.Transient(this)
