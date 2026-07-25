import Testing
@testable import FindlyKit

/// I7 hardening (docs/implementation-handoff.md "Known follow-ups") — `KeychainStoring` is the
/// protocol `FirebaseAuthProvider` (app target) will use instead of `UserDefaults` for the Firebase
/// phone-verification session id. Only the in-memory fake is exercised here (the real Keychain
/// implementation lives in the app target and is verified via `swiftc -typecheck`, per
/// mobile/ios/README.md); this suite covers the pure read/write/remove contract every conforming
/// type must satisfy.
struct KeychainStoringTests {

    @Test func returnsNilForAKeyThatWasNeverWritten() {
        let store = InMemoryKeychainStore()

        #expect(store.string(forKey: "missing") == nil)
    }

    @Test func readsBackExactlyWhatWasWritten() {
        let store = InMemoryKeychainStore()

        store.setString("session-abc", forKey: "verificationID")

        #expect(store.string(forKey: "verificationID") == "session-abc")
    }

    @Test func writingAgainOverwritesThePreviousValue() {
        let store = InMemoryKeychainStore()

        store.setString("first", forKey: "verificationID")
        store.setString("second", forKey: "verificationID")

        #expect(store.string(forKey: "verificationID") == "second")
    }

    @Test func removeClearsTheStoredValue() {
        let store = InMemoryKeychainStore()
        store.setString("session-abc", forKey: "verificationID")

        store.removeString(forKey: "verificationID")

        #expect(store.string(forKey: "verificationID") == nil)
    }

    @Test func removingAKeyThatWasNeverWrittenIsANoOp() {
        let store = InMemoryKeychainStore()

        store.removeString(forKey: "never-written")

        #expect(store.string(forKey: "never-written") == nil)
    }

    @Test func keysAreIndependent() {
        let store = InMemoryKeychainStore()

        store.setString("value-a", forKey: "keyA")
        store.setString("value-b", forKey: "keyB")

        #expect(store.string(forKey: "keyA") == "value-a")
        #expect(store.string(forKey: "keyB") == "value-b")
    }
}
