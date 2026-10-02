// swift-tools-version:6.0
import PackageDescription

// Test-only package. It compiles holzBar's pure macOS 27 logic so that logic can be
// unit tested with `swift test`. The same files are compiled into the holzBar app
// through the synchronized `holzBar` folder group.
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
    ]
)
