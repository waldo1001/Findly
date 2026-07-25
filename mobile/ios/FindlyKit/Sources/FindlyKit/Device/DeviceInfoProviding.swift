import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Supplies the platform/model/appVersion fields of a §4.1 registration request.
public protocol DeviceInfoProviding {
    var platform: String { get }
    var model: String { get }
    var appVersion: String { get }
}

/// A fixed-value implementation — used directly on non-iOS hosts (this package's macOS test/build
/// target) and in tests on any platform.
public struct StaticDeviceInfoProvider: DeviceInfoProviding {
    public let platform: String
    public let model: String
    public let appVersion: String

    public init(platform: String, model: String, appVersion: String) {
        self.platform = platform
        self.model = model
        self.appVersion = appVersion
    }
}

#if os(iOS) && canImport(UIKit)
/// The real on-device implementation.
public struct SystemDeviceInfoProvider: DeviceInfoProviding {
    public var platform: String { "ios" }
    public var model: String { UIDevice.current.model }
    public var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public init() {}
}
#endif
