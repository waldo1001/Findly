import Foundation

/// What `DeviceSettingsCoordinator.applySettings` must do about the pause/resume side of a
/// settings change (specs/009-device-runtime.md §3.5/§4).
public enum PauseAction: Equatable {
    case none
    case pause
    case resume
}

public struct SettingsChangeActions: Equatable {
    public let rebuildSchedule: Bool
    public let pauseAction: PauseAction
}

/// Pure decision function for specs/009-device-runtime.md §3.5: "on **any** path, if
/// `syncIntervalMinutes` changed the schedule MUST be rebuilt immediately... if `trackingEnabled`
/// changed, apply §4." `previous` is `nil` on the very first settings application this process has
/// ever seen (app cold start before any settings have been cached) — treated as "everything
/// changed" so a fresh install/process always ends up with a correctly (re)built schedule. A
/// straight port of Android's `SettingsChangeDecision` (`location/settings/SettingsChangeDecision.kt`).
public enum SettingsChangeDecision {
    public static func decide(previous: DeviceSettingsSnapshot?, next: DeviceSettingsSnapshot) -> SettingsChangeActions {
        let intervalChanged = previous == nil || previous?.syncIntervalMinutes != next.syncIntervalMinutes
        let trackingChanged = previous == nil || previous?.trackingEnabled != next.trackingEnabled

        let pauseAction: PauseAction
        if !trackingChanged {
            pauseAction = .none
        } else if !next.trackingEnabled {
            pauseAction = .pause
        } else {
            pauseAction = .resume
        }

        // A paused target has nothing to schedule. An active target rebuilds when the interval
        // itself changed, or when tracking just turned back on (resume must restore the schedule
        // even if the interval didn't change, §4) - either way that's "pauseAction == .resume".
        let rebuildSchedule = next.trackingEnabled && (intervalChanged || pauseAction == .resume)

        return SettingsChangeActions(rebuildSchedule: rebuildSchedule, pauseAction: pauseAction)
    }
}
