import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.4 / §10 "App lock" — the pure `shouldLock` policy:
/// `shouldLock(enabled, signedIn, isColdStart, backgroundedAt, now)`.
struct AppLockPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func disabled_neverLocks_evenOnColdStartAfterLongBackground() {
        #expect(!AppLockPolicy.shouldLock(enabled: false, signedIn: true, isColdStart: true, backgroundedAt: nil, now: now))
        #expect(!AppLockPolicy.shouldLock(enabled: false, signedIn: true, isColdStart: false, backgroundedAt: now - 3600, now: now))
    }

    @Test func signedOut_neverLocks() {
        #expect(!AppLockPolicy.shouldLock(enabled: true, signedIn: false, isColdStart: true, backgroundedAt: nil, now: now))
        #expect(!AppLockPolicy.shouldLock(enabled: true, signedIn: false, isColdStart: false, backgroundedAt: now - 3600, now: now))
    }

    @Test func coldStart_alwaysLocks_whenEnabledAndSignedIn() {
        #expect(AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: true, backgroundedAt: nil, now: now))
        #expect(AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: true, backgroundedAt: now - 1, now: now))
    }

    @Test func foreground_afterLessThanFiveMinutes_doesNotLock() {
        #expect(!AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: false, backgroundedAt: now - 299, now: now))
        #expect(!AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: false, backgroundedAt: now, now: now))
    }

    @Test func foreground_afterExactlyFiveMinutes_locks() {
        #expect(AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: false, backgroundedAt: now - 300, now: now))
        #expect(AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: false, backgroundedAt: now - 3600, now: now))
    }

    @Test func foreground_withoutBackgroundTimestamp_doesNotLock() {
        #expect(!AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: false, backgroundedAt: nil, now: now))
    }

    /// The clock moved backwards: the age cannot be trusted, and failing open here would let a
    /// clock change defeat the lock, so it locks.
    @Test func foreground_backgroundedAtInTheFuture_locks() {
        #expect(AppLockPolicy.shouldLock(enabled: true, signedIn: true, isColdStart: false, backgroundedAt: now + 60, now: now))
    }

    @Test func backgroundThreshold_isFiveMinutes() {
        #expect(AppLockPolicy.backgroundThreshold == 300)
    }
}

/// specs/010 §1.4 "Setting" / "Enabling" — the toggle's label, interactivity and caption.
struct AppLockToggleStateTests {
    @Test func label_followsBiometryType() {
        #expect(AppLockToggleState.make(capability: .init(canAuthenticate: true, biometry: .faceID), isEnabled: false).label == "Require Face ID to open Findly")
        #expect(AppLockToggleState.make(capability: .init(canAuthenticate: true, biometry: .touchID), isEnabled: false).label == "Require Touch ID to open Findly")
        #expect(AppLockToggleState.make(capability: .init(canAuthenticate: true, biometry: .opticID), isEnabled: false).label == "Require Optic ID to open Findly")
        #expect(AppLockToggleState.make(capability: .init(canAuthenticate: true, biometry: .none), isEnabled: false).label == "Require passcode to open Findly")
    }

    @Test func available_isInteractive_withoutCaption() {
        let state = AppLockToggleState.make(capability: .init(canAuthenticate: true, biometry: .faceID), isEnabled: false)
        #expect(state.isInteractive)
        #expect(state.caption == nil)
    }

    @Test func unavailableAndOff_isDisabled_withTheSpecCaption() {
        let state = AppLockToggleState.make(capability: .init(canAuthenticate: false, biometry: .none), isEnabled: false)
        #expect(!state.isInteractive)
        #expect(state.caption == "Set a screen lock on this phone first.")
        #expect(state.label == "Require passcode to open Findly")
    }

    /// Switching off needs no authentication, so a user whose device credential vanished after
    /// they enabled the lock must still be able to turn it off.
    @Test func unavailableButOn_staysInteractive_soItCanBeSwitchedOff() {
        let state = AppLockToggleState.make(capability: .init(canAuthenticate: false, biometry: .none), isEnabled: true)
        #expect(state.isInteractive)
        #expect(state.caption == nil)
    }
}

/// The VoiceOver / first-responder rules of the overlay window (`AppLockWindowPresenter`).
struct AppLockOverlayVisibilityTests {
    @Test func hidden_whenNeitherLockedNorCovered() {
        let v = AppLockOverlayVisibility(isLocked: false, isCoverVisible: false)
        #expect(!v.isVisible)
        #expect(!v.hidesOtherWindowsFromAccessibility)
        #expect(!v.resignsFirstResponder)
    }

    @Test func locked_hidesOtherWindows_resignsResponder_andMovesFocus() {
        let v = AppLockOverlayVisibility(isLocked: true, isCoverVisible: false)
        #expect(v.isVisible)
        #expect(v.hidesOtherWindowsFromAccessibility)
        #expect(v.resignsFirstResponder)
        #expect(v.movesAccessibilityFocusToOverlay)
    }

    @Test func coverOnly_hidesOtherWindows_butDoesNotStealFocus() {
        let v = AppLockOverlayVisibility(isLocked: false, isCoverVisible: true)
        #expect(v.isVisible)
        #expect(v.hidesOtherWindowsFromAccessibility)
        #expect(!v.resignsFirstResponder)
        #expect(!v.movesAccessibilityFocusToOverlay)
    }
}
