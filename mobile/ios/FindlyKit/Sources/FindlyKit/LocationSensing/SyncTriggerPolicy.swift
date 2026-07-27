import Foundation

/// specs/009-device-runtime.md §3.4 — the iOS opportunistic-trigger gate: "A capture is taken when
/// a trigger fires **and** at least `syncIntervalMinutes × 0.8` has elapsed since the last queued
/// fix (the 0.8 factor keeps a slightly-early system wake useful instead of wasted)." Pure decision
/// logic — no `BGTaskScheduler`/`CoreLocation` involved — called by whichever of the three §3.4
/// triggers (`BGAppRefreshTask`, significant-location-change, foreground) fires.
public enum SyncTriggerPolicy {
    public static func shouldCapture(syncIntervalMinutes: Int, lastQueuedFixAt: Date?, now: Date) -> Bool {
        guard let lastQueuedFixAt else { return true }
        let elapsed = now.timeIntervalSince(lastQueuedFixAt)
        let threshold = Double(syncIntervalMinutes) * 60 * 0.8
        return elapsed >= threshold
    }
}
