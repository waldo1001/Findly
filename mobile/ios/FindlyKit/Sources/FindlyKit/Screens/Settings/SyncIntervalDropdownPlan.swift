import Foundation

/// specs/010-app-shell-and-screen-ux.md §4.2, specs/001-api-contract.md §1.4/§9 — pure, no
/// SwiftUI/framework dependency, computing the `FindlyDropdownField` options for the Devices
/// screen's sync-interval control. `CLAUDE.md` is explicit that every limit is read from
/// `features` (derived server-side from `PLAN_MATRIX`), never hardcoded at a call site — this
/// type takes the floor as a parameter for exactly that reason; it never bakes in a number of its
/// own for `minSyncIntervalMinutes`.
public enum SyncIntervalDropdownPlan {
    /// The seven allowed `syncIntervalMinutes` values, exactly 001 §1.4's set, ascending.
    public static let allowedMinutes = [5, 10, 15, 30, 60, 120, 1440]

    /// Exact wording from 001 §4.2 ("5 min, 10 min, 15 min, 30 min, 1 hour, 2 hours, 1 day") —
    /// not the abbreviated "5m/1h/1d" the pre-010 chip row used.
    public static func label(for minutes: Int) -> String {
        switch minutes {
        case 60: return "1 hour"
        case 120: return "2 hours"
        case 1440: return "1 day"
        default: return "\(minutes) min"
        }
    }

    /// `floor` MUST come from the caller's `features.limits.minSyncIntervalMinutes` (001 §9) —
    /// this type has no default of its own and never invents one; the pre-disable is a UX
    /// convenience only, the server remains the source of truth (004 §3.2/§9's rule) for the
    /// `PATCH` itself.
    public static func options(minSyncIntervalMinutes floor: Int) -> [FindlyDropdownOption<Int>] {
        allowedMinutes.map { minutes in
            let isEnabled = minutes >= floor
            return FindlyDropdownOption(
                value: minutes,
                title: label(for: minutes),
                isEnabled: isEnabled,
                disabledReason: isEnabled ? nil : "Your plan requires at least \(label(for: floor))"
            )
        }
    }

    /// specs/010-app-shell-and-screen-ux.md §4.2, §9 (review fix, I36 round 2) — a `nil` floor
    /// (`features` hasn't loaded yet, or a future refactor reorders the two assignments that
    /// currently keep `state`/`minSyncIntervalMinutes` in lockstep) MUST fail CLOSED: every
    /// option disabled. `?? 0` was the earlier, wrong shape here — a floor of 0 disables
    /// nothing, since every allowed value is `>= 0`, so it fails OPEN and would let a user pick
    /// any interval with no plan check at all. Mirrors Android's
    /// `SyncIntervalOptions.buildForLimits`.
    public static func options(minSyncIntervalMinutes floor: Int?) -> [FindlyDropdownOption<Int>] {
        guard let floor else {
            return allowedMinutes.map { minutes in
                FindlyDropdownOption(
                    value: minutes,
                    title: label(for: minutes),
                    isEnabled: false,
                    disabledReason: "We couldn't confirm your plan's limits."
                )
            }
        }
        return options(minSyncIntervalMinutes: floor)
    }
}
