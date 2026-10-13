// swift-tools-version:6.2
import PackageDescription

// A throwaway spike (Preview) of SwiftUI's reordering API (macOS 27) for holzBar's Menu Bar
// Layout pane. It is not part of holzBar.app and nothing in the app uses it.
//
//   build:  swift build -c release --package-path Scripts/layout-reorder
//   run:    Scripts/layout-reorder/.build/release/layout-reorder-spike --help
//   test:   swift test --package-path Scripts/layout-reorder
//
// It asks for no permission, has no network code and no dependency, and builds with the Command
// Line Tools alone.
//
// The targets use the same Swift 6 settings as the app (see the package in the repository
// root): the library is plain, the executable has the main actor as its default isolation.
let spikeSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LayoutReorderSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LayoutReorderCore",
            path: "Sources/LayoutReorderCore",
            swiftSettings: spikeSettings
        ),
        .executableTarget(
            name: "layout-reorder-spike",
            dependencies: ["LayoutReorderCore"],
            path: "Sources/layout-reorder-spike",
            swiftSettings: spikeSettings + [.defaultIsolation(MainActor.self)]
        ),
    ]
)
