import Foundation

/// specs/009-device-runtime.md §1 (pipeline) + §1.2 (suppression) — the capture-and-queue pipeline,
/// mirroring Android's `FixCaptureCoordinator` split exactly: a thin, CoreLocation-touching
/// `LocationProviding` implementation on one side, and this pure, fake-testable `actor` on the
/// other, which owns:
///
/// - **Suppression** (§1.2): a capture is skipped (not queued, never an error) when tracking is
///   paused, location permission is absent, or an identical-position fix was captured < 60 s ago.
/// - **Ordering**: paused/permission-absent are checked **before** ever invoking the provider (no
///   GPS burn at all); pause is re-checked again **after** capture too, so a pause landing
///   mid-capture drops the result instead of queuing it (specs/009 §4: "in-flight captures dropped,
///   not queued"); the debounce check can only run after a fix comes back (hint or real capture).
///
/// This is **the** seam every I10-owned trigger (the periodic BG-task/significant-location-change
/// path, a future manual-refresh UI call) goes through. `source: .locate` is deliberately **not**
/// routed through here (mirrors Android's `LocateRequestPushHandler` bypassing
/// `FixCaptureCoordinator` and calling `LocationCapturer`/here, `LocationProviding.requestSingleFix`
/// directly) — a `LOCATE_REQUEST` MUST still be fulfilled while paused (specs/009 §5.1), which
/// this class's pause gate would incorrectly block. `hint` is the seam I11's geofence-transition
/// handling calls for its own `source: "geofence"` fix (§6.3: "MAY reuse the transition's own
/// coordinates") and the one `SystemLocationProvider`'s own significant-location-change delegate
/// callback uses (see `LocationProviding.swift`'s doc) — when supplied, `LocationProviding` is
/// never invoked at all, so a hint burns no extra GPS.
public actor FixCaptureCoordinator {
    private let provider: LocationProviding
    private let queue: FixQueue
    private let isPaused: () -> Bool
    private let isPermissionGranted: () -> Bool
    private let now: () -> Date

    private var lastCaptured: (lat: Double, lon: Double, at: Date)?

    public init(
        provider: LocationProviding,
        queue: FixQueue,
        isPaused: @escaping () -> Bool,
        isPermissionGranted: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.queue = queue
        self.isPaused = isPaused
        self.isPermissionGranted = isPermissionGranted
        self.now = now
    }

    /// Captures one fix for `source` and enqueues it, unless suppressed. Returns the
    /// captured/reused fix even when it was ultimately debounce-suppressed post-capture is
    /// intentionally NOT the behavior here (unlike Android's `CapturedFix`-returning variant) —
    /// `nil` always means "nothing was queued", full stop; iOS has no caller today that needs the
    /// position separately from the enqueue outcome (Android's geofence-event handler does, but
    /// that's I11's concern and can widen this return value then if needed).
    @discardableResult
    public func captureAndQueue(source: FixSource, hint: LocationFix? = nil) async -> LocationFix? {
        if isPaused() { return nil }
        if !isPermissionGranted() { return nil }

        let fix: LocationFix
        if let hint {
            fix = hint
        } else {
            guard let captured = try? await provider.requestSingleFix(source: source) else { return nil }
            fix = captured
        }

        // Pause arriving mid-capture: drop, don't queue (specs/009 §4).
        if isPaused() { return nil }

        if isDuplicateWithinDebounce(fix) { return nil }
        lastCaptured = (fix.lat, fix.lon, now())

        await queue.enqueue(fix)
        return fix
    }

    /// specs/009 §1.2: "an identical-position fix was captured < 60 s ago (debounce against
    /// duplicate platform callbacks)."
    private func isDuplicateWithinDebounce(_ fix: LocationFix) -> Bool {
        guard let lastCaptured else { return false }
        let samePosition = lastCaptured.lat == fix.lat && lastCaptured.lon == fix.lon
        let withinDebounceWindow = now().timeIntervalSince(lastCaptured.at) < 60
        return samePosition && withinDebounceWindow
    }
}
