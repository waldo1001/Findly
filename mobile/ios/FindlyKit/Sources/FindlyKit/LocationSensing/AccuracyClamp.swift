import Foundation

/// specs/001-api-contract.md §5.1 (I50 fix 7, Minor) — the backend enforces `accuracyM` in
/// `[0, 10000]`; a value outside that range is a `400 VALIDATION_FAILED` that kills the WHOLE batch
/// (a definitive rejection). Pure, `Foundation`-only clamp so both real call sites — `CLVisit.
/// horizontalAccuracy` (undocumented range; new with I50's visit monitoring) and `CLLocation.
/// horizontalAccuracy` (documented to go negative when invalid — pre-existing) — can share one
/// tested implementation instead of each hand-rolling `max(0, min(value, 10_000))` inline.
public enum AccuracyClamp {
    public static func clamp(_ accuracyM: Double) -> Double {
        min(max(accuracyM, 0), 10_000)
    }
}
