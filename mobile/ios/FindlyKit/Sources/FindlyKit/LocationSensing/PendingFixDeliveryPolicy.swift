import Foundation

/// specs/009-device-runtime.md §1.1's accuracy table / 001-api-contract.md §6.3 (I52 review round 2,
/// finding 3, Major) — whether a location delivery is accurate enough to resume the pending
/// `requestSingleFix` callers currently waiting on it, given the highest accuracy TIER among them.
///
/// Before this policy existed, `SystemLocationProvider.didUpdateLocations` resumed EVERY pending
/// caller with whatever CoreLocation delivered, no matter how coarse — harmless while the shared
/// `CLLocationManager` was only ever used for one-shot captures. With the §1.3 presence session now
/// keeping that SAME manager continuously updating at `distanceFilter = 500`/kilometre accuracy, a
/// delivery arrives routinely while a high-accuracy (`.locate`/`.manual`) caller is ALSO pending —
/// including CoreLocation's immediate cached delivery right after a `desiredAccuracy` write. So a
/// `LOCATE_REQUEST` had a live thirty-second window in which a roughly 3000 m presence position
/// could be resumed as the locate result and fulfilled `source: "locate"` — violating §1.1's
/// accuracy table and 001 §6.3. The drain rule (`PresenceAccuracyPolicy`) protects the presence
/// session from a one-shot capture; this policy is what protects a pending locate from the presence
/// session's own coarse stream.
///
/// Pure and CoreLocation-free — `horizontalAccuracyMeters` is a plain `Double` (`CLLocationDistance`
/// is only a type alias for it), so this is testable without CoreLocation, in the same shape as
/// `FixAccuracyPolicy`/`PresenceAccuracyPolicy`. `SystemLocationProvider.didUpdateLocations`
/// consults it, via `PendingFixContinuations.resumeAllIfAcceptableAndAct`, BEFORE draining the
/// registry — on a rejection, the registry is left completely untouched, so the still-pending
/// caller falls through to the significant-location-change/visit hint path and is resolved later by
/// its own timeout or a subsequent, better delivery.
public enum PendingFixDeliveryPolicy {
    /// Comfortably above `.balanced`'s own ~100 m-class accuracy (specs/009 §1.1's table), so a
    /// genuine balanced-tier delivery is never wrongly rejected even while a `.high` caller also
    /// happens to be pending — and comfortably below the presence session's ~3 km baseline
    /// (`kCLLocationAccuracyThreeKilometers`), so a presence-session delivery is always rejected
    /// when a high-accuracy caller is the one waiting on it.
    public static let highAccuracyThresholdMeters: Double = 200

    /// `highestPendingTier` is `nil` when nothing is pending — `PendingFixContinuations` never
    /// actually calls this in that case (there is nothing to gate), but the signature stays
    /// `Optional` to match the `max()`-over-a-possibly-empty-collection shape that produces it.
    /// Only a `.high` pending tier can ever cause a rejection: a `.balanced`-only pending set never
    /// asked for anything better than what the presence stream already provides, so it accepts
    /// unconditionally.
    public static func shouldResumePendingFixes(highestPendingTier: LocationAccuracyTier?, horizontalAccuracyMeters: Double) -> Bool {
        guard highestPendingTier == .high else { return true }
        return horizontalAccuracyMeters <= highAccuracyThresholdMeters
    }
}
