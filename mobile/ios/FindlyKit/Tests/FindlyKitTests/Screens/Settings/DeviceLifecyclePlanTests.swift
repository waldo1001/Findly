import Testing
@testable import FindlyKit

/// specs/011 §1.1, §4.4; specs/010 §4.2 bullet 5 — the pure card-row decisions.
struct DeviceLifecyclePlanTests {
    // MARK: Remove-action visibility: {parent, owner, neither} x {this device, other device}

    @Test func parent_seesRemove_onAnotherMembersDevice() {
        #expect(DeviceLifecyclePlan.showsRemove(isParent: true, callerUserId: "u1", ownerUserId: "u2", deviceId: "d2", thisDeviceId: "d1"))
    }

    @Test func owner_nonParent_seesRemove_onOwnOtherDevice() {
        #expect(DeviceLifecyclePlan.showsRemove(isParent: false, callerUserId: "u2", ownerUserId: "u2", deviceId: "d2", thisDeviceId: "d1"))
    }

    @Test func neither_parentNorOwner_doesNotSeeRemove() {
        #expect(!DeviceLifecyclePlan.showsRemove(isParent: false, callerUserId: "u1", ownerUserId: "u2", deviceId: "d2", thisDeviceId: "d1"))
    }

    @Test func neverOnThisDevice_evenForParentAndOwner() {
        #expect(!DeviceLifecyclePlan.showsRemove(isParent: true, callerUserId: "u1", ownerUserId: "u1", deviceId: "d1", thisDeviceId: "d1"))
        #expect(!DeviceLifecyclePlan.showsRemove(isParent: false, callerUserId: "u1", ownerUserId: "u1", deviceId: "d1", thisDeviceId: "d1"))
        #expect(!DeviceLifecyclePlan.showsRemove(isParent: true, callerUserId: "u1", ownerUserId: "u2", deviceId: "d1", thisDeviceId: "d1"))
    }

    @Test func unknownCaller_nonParent_doesNotSeeRemove_butParentStillDoes() {
        #expect(!DeviceLifecyclePlan.showsRemove(isParent: false, callerUserId: nil, ownerUserId: "u2", deviceId: "d2", thisDeviceId: nil))
        #expect(DeviceLifecyclePlan.showsRemove(isParent: true, callerUserId: nil, ownerUserId: "u2", deviceId: "d2", thisDeviceId: nil))
    }

    // MARK: Nudge toggle: owned devices only, any role

    @Test func nudgeToggle_onlyOnOwnedDevices() {
        #expect(DeviceLifecyclePlan.showsNudgeToggle(callerUserId: "u1", ownerUserId: "u1"))
        #expect(!DeviceLifecyclePlan.showsNudgeToggle(callerUserId: "u1", ownerUserId: "u2"))
        #expect(!DeviceLifecyclePlan.showsNudgeToggle(callerUserId: nil, ownerUserId: "u2"))
    }

    // MARK: Last seen line + chip

    @Test func lastSeenLine_isOmittedWhenAbsent() {
        #expect(DeviceLifecyclePlan.lastSeenText(lastSeenAt: nil, nowIso: "2026-07-19T10:00:00Z") == nil)
    }

    @Test func lastSeenLine_usesTheRelativeTimeFormatter() {
        #expect(DeviceLifecyclePlan.lastSeenText(lastSeenAt: "2026-07-19T09:00:00Z", nowIso: "2026-07-19T10:00:00Z") == "Last seen 1 hr ago")
    }

    @Test func statusChip_dormantReplacesActive() {
        #expect(DeviceLifecyclePlan.statusLabel(isDormant: true, trackingEnabled: true) == "Inactive")
        #expect(DeviceLifecyclePlan.statusLabel(isDormant: false, trackingEnabled: true) == "Active")
        #expect(DeviceLifecyclePlan.statusLabel(isDormant: false, trackingEnabled: false) == "Paused")
    }

    @Test func statusChip_dormantWinsOverPaused() {
        // 011 §1.1: Inactive appears "in place of Active"; a paused dormant device is still silent
        // for >30 days, which is what the owner needs to see on a ghost.
        #expect(DeviceLifecyclePlan.statusLabel(isDormant: true, trackingEnabled: false) == "Inactive")
    }

    // MARK: Copy (011 §1.1, normative)

    @Test func confirmationCopy_isNormative() {
        #expect(DeviceLifecyclePlan.confirmationTitle(deviceName: "Noor's phone") == "Remove \"Noor's phone\"?")
        #expect(DeviceLifecyclePlan.confirmationBody == "Its last known location is deleted. Location history stays until it expires. If this phone still has Findly, it will reappear the next time Findly opens on it.")
    }
}
