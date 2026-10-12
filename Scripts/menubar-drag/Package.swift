// swift-tools-version:6.2
import PackageDescription

// A throwaway spike probe (Preview) that measures moving menu bar items by drag, without
// holding Command, on macOS 26 and 27. It is not part of holzBar.app and nothing in the app
// uses it.
//
//   build:  swift build -c release --package-path Scripts/menubar-drag
//   run:    Scripts/menubar-drag/.build/release/menubar-drag-probe --help
//   test:   swift test --package-path Scripts/menubar-drag
//
// It needs the terminal to have Accessibility and has no network code. It has no dependency
// and builds with the Command Line Tools alone.
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
    name: "MenuBarDragSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MenuBarDragCore",
            path: "Sources/MenuBarDragCore",
            swiftSettings: spikeSettings
        ),
        .executableTarget(
            name: "menubar-drag-probe",
            dependencies: ["MenuBarDragCore"],
            path: "Sources/menubar-drag-probe",
            swiftSettings: spikeSettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MenuBarDragCoreTests",
            dependencies: ["MenuBarDragCore"],
            path: "Tests/MenuBarDragCoreTests",
            swiftSettings: spikeSettings
        ),
    ]
)
