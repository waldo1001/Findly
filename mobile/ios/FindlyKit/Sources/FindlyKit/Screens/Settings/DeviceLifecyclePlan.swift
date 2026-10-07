import Foundation

/// specs/011-device-lifecycle-and-staleness.md §1.1, §4.4; specs/010 §4.2 bullet 5 — the pure
/// decisions behind a Devices card's lifecycle rows, kept out of the SwiftUI view so the visibility
/// matrix is unit-testable (010 §10 "Device lifecycle").
public enum DeviceLifecyclePlan {
    /// 011 §1.1: Remove is offered when the caller is a parent OR owns the card's device — and
    /// NEVER on the card of the device this app is running on (removing yourself would just
    /// re-register on the next call). Not parent-gated: owners may remove their own devices.
    public static func showsRemove(
        isParent: Bool, callerUserId: String?, ownerUserId: String, deviceId: String, thisDeviceId: String?
    ) -> Bool {
        if let thisDeviceId, deviceId == thisDeviceId { return false }
        return isParent || isOwner(callerUserId: callerUserId, ownerUserId: ownerUserId)
    }

    /// 011 §4.4: `Remind me when sharing stops` is the device OWNER's own preference — shown on
    /// devices the caller owns, in any role, and never on another member's device.
    public static func showsNudgeToggle(callerUserId: String?, ownerUserId: String) -> Bool {
        isOwner(callerUserId: callerUserId, ownerUserId: ownerUserId)
    }

    /// 011 §1.1: a muted `Last seen <relative time>` line; omitted entirely when `lastSeenAt` is absent.
    public static func lastSeenText(lastSeenAt: String?, nowIso: String) -> String? {
        guard let lastSeenAt else { return nil }
        return "Last seen \(RelativeTimeFormatter.format(recordedAtIso: lastSeenAt, nowIso: nowIso))"
    }

    /// 011 §1.1/§2: a dormant device shows **Inactive** in place of Active.
    public static func statusLabel(isDormant: Bool, trackingEnabled: Bool) -> String {
        if isDormant { return "Inactive" }
        return trackingEnabled ? "Active" : "Paused"
    }

    /// 011 §1.1 (normative copy, English per 000 §O8).
    public static func confirmationTitle(deviceName: String) -> String {
        "Remove \"\(deviceName)\"?"
    }

    public static let confirmationBody =
        "Its last known location is deleted. Location history stays until it expires. "
        + "If this phone still has Findly, it will reappear the next time Findly opens on it."

    public static let authForbiddenMessage = "Only a parent can remove another member's device."

    private static func isOwner(callerUserId: String?, ownerUserId: String) -> Bool {
        guard let callerUserId else { return false }
        return callerUserId == ownerUserId
    }
}
