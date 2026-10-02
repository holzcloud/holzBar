// swift-tools-version:6.0
import PackageDescription

// Test-only package. It compiles holzBar's pure logic, `holzBar/Core` (any macOS) and
// `holzBar/MenuBar/MacOS27/Core` (macOS 27), so it can be unit tested with `swift test`.
// The app compiles the same files through the synchronized `holzBar` folder group.
let package = Package(
    name: "HolzBarMacOS27Core",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HolzBarMacOS27Core",
            path: "holzBar/MenuBar/MacOS27/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HolzBarMacOS27CoreTests",
            dependencies: ["HolzBarMacOS27Core"],
            path: "Tests/HolzBarMacOS27CoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "HolzBarCore",
            path: "holzBar/Core",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HolzBarCoreTests",
            dependencies: ["HolzBarCore"],
            path: "Tests/HolzBarCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
