// swift-tools-version:6.2
import PackageDescription

// A throwaway spike that ships nothing: it measures on a Mac whether a process signed ad hoc
// with the hardened runtime and no entitlement can read and set a display's brightness through
// macOS's private display interface, and whether the default output device's volume can be
// read, set, muted and listened to through public CoreAudio. It builds with the Command Line
// Tools alone and is not part of holzBar.app, the root test package or the Xcode project.
// No dependency, no network.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "DisplayControlsProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DisplayProbeCore",
            swiftSettings: settings
        ),
        .executableTarget(
            name: "display-controls-probe",
            dependencies: ["DisplayProbeCore"],
            swiftSettings: settings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .testTarget(
            name: "DisplayProbeCoreTests",
            dependencies: ["DisplayProbeCore"],
            swiftSettings: settings
        ),
    ]
)
