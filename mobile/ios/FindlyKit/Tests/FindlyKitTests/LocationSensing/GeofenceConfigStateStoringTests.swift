import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §6.1 — the cached geofence config document + ETag. Mirrors
/// `DeviceSettingsStateStoring`'s test coverage shape.
struct GeofenceConfigStateStoringTests {

    func makeGeofence(_ id: String = "gf_home") -> Geofence {
        Geofence(geofenceId: id, name: "Home", lat: 51.0, lon: 3.7, radiusM: 150, icon: "home", notifyOnEnter: true, notifyOnExit: true)
    }

    @Test func inMemory_startsEmpty() {
        let store = InMemoryGeofenceConfigStateStore()
        #expect(store.current() == nil)
    }

    @Test func inMemory_update_thenCurrent_roundTrips() {
        let store = InMemoryGeofenceConfigStateStore()
        let config = CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()])

        store.update(config)

        #expect(store.current() == config)
    }

    @Test func inMemory_clear_dropsTheCachedDocument() {
        let store = InMemoryGeofenceConfigStateStore(initial: CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()]))

        store.clear()

        #expect(store.current() == nil)
    }

    @Test func userDefaults_startsEmpty_onAFreshSuite() {
        let defaults = UserDefaults(suiteName: "GeofenceConfigStateStoringTests.\(UUID().uuidString)")!
        let store = UserDefaultsGeofenceConfigStateStore(defaults: defaults)
        #expect(store.current() == nil)
    }

    @Test func userDefaults_update_thenCurrent_roundTripsAcrossAFreshInstance() {
        let defaults = UserDefaults(suiteName: "GeofenceConfigStateStoringTests.\(UUID().uuidString)")!
        let config = CachedGeofenceConfig(etag: "\"0x2\"", geofences: [makeGeofence("gf_home"), makeGeofence("gf_school")])
        UserDefaultsGeofenceConfigStateStore(defaults: defaults).update(config)

        // A fresh instance over the SAME UserDefaults suite - proves persistence isn't just an
        // in-memory property of the store object itself.
        let reopened = UserDefaultsGeofenceConfigStateStore(defaults: defaults)
        #expect(reopened.current() == config)
    }

    @Test func userDefaults_clear_dropsBothKeys() {
        let defaults = UserDefaults(suiteName: "GeofenceConfigStateStoringTests.\(UUID().uuidString)")!
        let store = UserDefaultsGeofenceConfigStateStore(defaults: defaults)
        store.update(CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()]))

        store.clear()

        #expect(store.current() == nil)
    }

    @Test func userDefaults_emptyGeofencesList_stillRoundTrips() {
        // The "family with no config yet" sentinel (001 §7.1: `{ version: 0, geofences: [] }`,
        // `ETag: "0"`) - must not be confused with "nothing cached" (nil).
        let defaults = UserDefaults(suiteName: "GeofenceConfigStateStoringTests.\(UUID().uuidString)")!
        let store = UserDefaultsGeofenceConfigStateStore(defaults: defaults)
        store.update(CachedGeofenceConfig(etag: "0", geofences: []))

        #expect(store.current() == CachedGeofenceConfig(etag: "0", geofences: []))
    }
}
