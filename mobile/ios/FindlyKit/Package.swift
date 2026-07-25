// swift-tools-version:5.10
// Findly — iOS client foundation (specs/004-ios-client.md).
// Everything lives in this package so it builds & tests headlessly (`swift build` / `swift test`)
// on any host, including a plain macOS session with no Xcode/simulator. The thin SwiftUI app
// target in ../Findly/ depends on this package as a local dependency.
import PackageDescription

let package = Package(
    name: "FindlyKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "FindlyKit", targets: ["FindlyKit"])
    ],
    targets: [
        .target(
            name: "FindlyKit",
            path: "Sources/FindlyKit"
        ),
        .testTarget(
            name: "FindlyKitTests",
            dependencies: ["FindlyKit"],
            path: "Tests/FindlyKitTests",
            swiftSettings: [
                // Compatibility shim for hosts with only Xcode Command Line Tools installed (no
                // Xcode.app) — Testing.framework exists there but `swift test` doesn't add its
                // framework/plugin search paths by default. No-op on hosts where these paths don't
                // exist (a full Xcode install finds its own Testing.framework normally).
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ]
)
