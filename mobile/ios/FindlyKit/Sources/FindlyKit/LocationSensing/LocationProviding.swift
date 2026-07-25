import Foundation
#if os(iOS) && canImport(CoreLocation)
import CoreLocation
#endif

/// specs/004-ios-client.md §7 — foreground high-accuracy fix + background significant-change
/// monitoring, behind a protocol so `FixQueue`/`DeviceRegistrationService` consumers are testable
/// without CoreLocation. The real on-device wiring (staged When-In-Use → Always authorization, 000
/// §O1; significant-change monitoring; single-fix requests bridged to async/await) is a runtime
/// TODO for the on-device build — it cannot be exercised without a device/simulator, which this
/// session doesn't have.
public protocol LocationProviding: AnyObject {
    func requestSingleFix() async throws -> LocationFix
    func startBackgroundMonitoring(into queue: FixQueue)
    func stopBackgroundMonitoring()
}

public enum LocationProvidingError: Error, Equatable {
    case notImplemented
}

/// Test/macOS-build default — always fails `requestSingleFix`, background monitoring is inert.
public final class NoOpLocationProvider: LocationProviding {
    public init() {}
    public func requestSingleFix() async throws -> LocationFix { throw LocationProvidingError.notImplemented }
    public func startBackgroundMonitoring(into queue: FixQueue) {}
    public func stopBackgroundMonitoring() {}
}

#if os(iOS) && canImport(CoreLocation)
/// The real on-device implementation — scaffolded, not yet wired to `CLLocationManagerDelegate`.
public final class SystemLocationProvider: NSObject, LocationProviding {
    private let manager = CLLocationManager()

    public override init() {
        super.init()
        // TODO(on-device session): manager.delegate = self; staged authorization request
        // (requestWhenInUseAuthorization, then an explicit in-app upgrade prompt before
        // requestAlwaysAuthorization — 000 §O1's "Always" onboarding dance).
    }

    public func requestSingleFix() async throws -> LocationFix {
        // TODO(on-device session): manager.requestLocation(), bridge the delegate callback to
        // async/await via a checked continuation, map CLLocation -> LocationFix (source: .manual
        // or .locate depending on caller).
        throw LocationProvidingError.notImplemented
    }

    public func startBackgroundMonitoring(into queue: FixQueue) {
        // TODO(on-device session): manager.startMonitoringSignificantLocationChanges(); bridge
        // delegate callbacks into `queue.enqueue(_:)` (source: .periodic).
    }

    public func stopBackgroundMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
    }
}
#endif
