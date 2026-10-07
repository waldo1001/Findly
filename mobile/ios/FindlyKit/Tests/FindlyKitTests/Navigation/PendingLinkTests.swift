import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.3 (H20 / 000 §D20, row I63) — the pending link's pure
/// decisions, its slot (memory + local storage) and the `UserDefaults` store. Codes below are
/// obviously fictional (007 §7).
@MainActor
struct PendingLinkTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func link(_ kind: PendingLinkKind = .familyInvite, code: String = "7F3K9QRZ", at date: Date? = nil) -> PendingLink {
        PendingLink(kind: kind, code: code, receivedAt: date ?? t0)
    }

    private let ready = LinkActState(isSignedIn: true, isLaunchResolved: true, isLocked: false)
    private let notReady = LinkActState(isSignedIn: false, isLaunchResolved: true, isLocked: false)

    // MARK: - Capture decision (010 §1.3 "Capture")

    @Test func capture_signedOut_stores() {
        let state = LinkActState(isSignedIn: false, isLaunchResolved: true, isLocked: false)
        #expect(PendingLinkPolicy.captureDecision(state) == .store)
    }

    @Test func capture_launchNotResolved_stores() {
        let state = LinkActState(isSignedIn: true, isLaunchResolved: false, isLocked: false)
        #expect(PendingLinkPolicy.captureDecision(state) == .store)
    }

    @Test func capture_locked_stores_soAnI64LockCanReuseTheSlot() {
        let state = LinkActState(isSignedIn: true, isLaunchResolved: true, isLocked: true)
        #expect(PendingLinkPolicy.captureDecision(state) == .store)
    }

    @Test func capture_signedInResolvedUnlocked_navigatesNow() {
        #expect(PendingLinkPolicy.captureDecision(ready) == .navigateNow)
    }

    // MARK: - Replay decision (010 §1.3 "Replay", "Persistence")

    @Test func replay_noPendingLink_waits() {
        #expect(PendingLinkPolicy.replayDecision(pending: nil, now: t0, state: ready) == .wait)
    }

    @Test func replay_validAndAppCanAct_replays() {
        let pending = link()
        #expect(PendingLinkPolicy.replayDecision(pending: pending, now: t0.addingTimeInterval(60), state: ready) == .replay(pending))
    }

    @Test func replay_validButAppCannotActYet_waits() {
        #expect(PendingLinkPolicy.replayDecision(pending: link(), now: t0.addingTimeInterval(60), state: notReady) == .wait)
    }

    @Test func replay_lockedStateWaits() {
        let locked = LinkActState(isSignedIn: true, isLaunchResolved: true, isLocked: true)
        #expect(PendingLinkPolicy.replayDecision(pending: link(), now: t0, state: locked) == .wait)
    }

    @Test func replay_justUnderOneHour_stillValid() {
        let pending = link()
        #expect(PendingLinkPolicy.replayDecision(pending: pending, now: t0.addingTimeInterval(3599), state: ready) == .replay(pending))
    }

    @Test func replay_atExactlyOneHour_expires() {
        #expect(PendingLinkPolicy.replayDecision(pending: link(), now: t0.addingTimeInterval(3600), state: ready) == .discard)
    }

    @Test func replay_expiredIsDiscardedEvenWhileTheAppCannotActYet() {
        #expect(PendingLinkPolicy.replayDecision(pending: link(), now: t0.addingTimeInterval(7200), state: notReady) == .discard)
    }

    @Test func replay_receivedInTheFuture_clockWentBackwards_isDiscarded() {
        #expect(PendingLinkPolicy.replayDecision(pending: link(), now: t0.addingTimeInterval(-10), state: ready) == .discard)
    }

    // MARK: - Slot (memory + local storage)

    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func makeSlot(store: PendingLinkStoring = InMemoryPendingLinkStore(), now: Date? = nil) -> (PendingLinkSlot, Clock) {
        let clock = Clock(now ?? t0)
        return (PendingLinkSlot(store: store, now: { clock.now }), clock)
    }

    @Test func slot_newerLinkReplacesOlder_oneSlotOnly() {
        let (slot, _) = makeSlot()
        slot.put(link(.familyInvite, code: "7F3K9QRZ"))
        slot.put(link(.groupJoin, code: "AAAA2222"))

        #expect(slot.take(ready) == link(.groupJoin, code: "AAAA2222"))
        #expect(slot.take(ready) == nil)
    }

    @Test func slot_take_clearsBeforeReturning_replayHappensOnce() {
        let store = InMemoryPendingLinkStore()
        let (slot, _) = makeSlot(store: store)
        slot.put(link())

        let first = slot.take(ready)

        #expect(first == link())
        #expect(store.load() == nil, "the slot is cleared first, so a crash mid-navigation cannot replay twice")
        #expect(slot.take(ready) == nil)
    }

    @Test func slot_take_whileAppCannotAct_keepsTheLink() {
        let (slot, _) = makeSlot()
        slot.put(link())

        #expect(slot.take(notReady) == nil)
        #expect(slot.take(ready) == link())
    }

    @Test func slot_take_expiredLink_isDiscardedSilentlyAndRemovedFromStorage() {
        let store = InMemoryPendingLinkStore()
        let (slot, clock) = makeSlot(store: store)
        slot.put(link())
        clock.now = t0.addingTimeInterval(3600)

        #expect(slot.take(ready) == nil)
        #expect(store.load() == nil)
    }

    @Test func slot_survivesProcessDeath_aFreshSlotOverTheSameStoreSeesTheLink() {
        let store = InMemoryPendingLinkStore()
        let (first, _) = makeSlot(store: store)
        first.put(link())

        let (afterRestart, _) = makeSlot(store: store, now: t0.addingTimeInterval(600))

        #expect(afterRestart.take(ready) == link())
    }

    @Test func slot_clear_removesMemoryAndStorage() {
        let store = InMemoryPendingLinkStore()
        let (slot, _) = makeSlot(store: store)
        slot.put(link())

        slot.clear()

        #expect(store.load() == nil)
        #expect(slot.take(ready) == nil)
    }

    @Test func pendingLink_description_neverContainsTheCode() {
        let text = "\(link(code: "7F3K9QRZ")) \(String(reflecting: link(code: "7F3K9QRZ")))"
        #expect(!text.contains("7F3K9QRZ"), "specs/010 §1.3 — the value MUST NOT be logged")
    }

    // MARK: - UserDefaults store

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "com.findly.tests.pendinglink.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func userDefaultsStore_roundTrips_andClears() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsPendingLinkStore(defaults: defaults)
        #expect(store.load() == nil)

        store.save(link(.groupJoin, code: "AAAA2222"))
        #expect(UserDefaultsPendingLinkStore(defaults: defaults).load() == link(.groupJoin, code: "AAAA2222"))

        store.clear()
        #expect(store.load() == nil)
    }

    @Test func userDefaultsStore_corruptValue_readsAsNilAndIsRemoved() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("not json".utf8), forKey: UserDefaultsPendingLinkStore.key)
        let store = UserDefaultsPendingLinkStore(defaults: defaults)

        #expect(store.load() == nil)
        #expect(defaults.object(forKey: UserDefaultsPendingLinkStore.key) == nil)
    }

    @Test func userDefaultsStore_unknownKind_readsAsNil() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"kind":"somethingElse","code":"7F3K9QRZ","receivedAt":0}"#.utf8), forKey: UserDefaultsPendingLinkStore.key)

        #expect(UserDefaultsPendingLinkStore(defaults: defaults).load() == nil)
    }
}
