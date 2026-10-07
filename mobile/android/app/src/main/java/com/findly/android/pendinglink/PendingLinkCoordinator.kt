package com.findly.android.pendinglink

/** Glue of [PendingLinkPolicy] and [PendingLinkStore] (specs/010 section 1.3); pure, clock passed in. */
class PendingLinkCoordinator(val store: PendingLinkStore) {

    /** Applies the capture decision: stores when the app cannot act yet; the caller navigates on
     * [CaptureDecision.NavigateNow]. */
    fun onIncoming(link: IncomingLink?, state: LinkAppState, now: Long): CaptureDecision {
        val decision = PendingLinkPolicy.capture(link, state)
        if (decision is CaptureDecision.Store) {
            val code = requireNotNull(decision.link.code)
            store.save(PendingLink(decision.link.kind, code, receivedAt = now))
        }
        return decision
    }

    /** Replays the pending link exactly once: clears the slot FIRST, then calls [navigate].
     * An expired link is discarded silently. Returns whether [navigate] ran. */
    fun replayIfReady(state: LinkAppState, now: Long, navigate: (PendingLink) -> Unit): Boolean =
        when (val decision = PendingLinkPolicy.replay(store.current.value, now, state)) {
            is ReplayDecision.Replay -> {
                store.clear()
                navigate(decision.link)
                true
            }
            ReplayDecision.Discard -> {
                store.clear()
                false
            }
            ReplayDecision.Wait -> false
        }
}
