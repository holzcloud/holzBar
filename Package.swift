// swift-tools-version:6.2
import PackageDescription

// Test-only package. It compiles holzBar's pure logic, `holzBar/Core` (any macOS) and
// `holzBar/MenuBar/MacOS27/Core` (macOS 27), so it can be unit tested with `swift test`.
// The app compiles the same files through the synchronized `holzBar` folder group.
// It also compiles `Shared/CodeSigning`, the code signing helpers shared by the app and the XPC service.
//
// The targets use the app's concurrency settings, so the tests check the semantics the app
// ships: Swift 6 language mode with approachable concurrency (SWIFT_APPROACHABLE_CONCURRENCY)
// and member import visibility everywhere, and the main actor as the default isolation for
// the app's Core code (SWIFT_DEFAULT_ACTOR_ISOLATION). The code signing helpers keep
// nonisolated as their default, as in the XPC service.
let approachableConcurrency: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let appCore = approachableConcurrency + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "HolzBarMacOS27Core",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HolzBarMacOS27Core",
            path: "holzBar/MenuBar/MacOS27/Core",
            swiftSettings: appCore
        ),
        .testTarget(
            name: "HolzBarMacOS27CoreTests",
            dependencies: ["HolzBarMacOS27Core"],
            path: "Tests/HolzBarMacOS27CoreTests",
            swiftSettings: approachableConcurrency
        ),
        .target(
            name: "HolzBarCore",
            path: "holzBar/Core",
            swiftSettings: appCore
        ),
        .testTarget(
            name: "HolzBarCoreTests",
            dependencies: ["HolzBarCore"],
            path: "Tests/HolzBarCoreTests",
            swiftSettings: approachableConcurrency
        ),
        .target(
            name: "SharedCodeSigning",
            path: "Shared/CodeSigning",
            swiftSettings: approachableConcurrency
        ),
        .testTarget(
            name: "SharedCodeSigningTests",
            dependencies: ["SharedCodeSigning"],
            path: "Tests/SharedCodeSigningTests",
            swiftSettings: approachableConcurrency
        ),
    ]
)
