package com.findly.android.queue

/** A frozen, stable-`batchId` slice of pending fixes (specs/003-android-client.md §10.1/§10.2). */
data class FixBatch(val batchId: String, val fixes: List<QueuedFix>)
