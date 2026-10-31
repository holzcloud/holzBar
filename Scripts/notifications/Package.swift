// swift-tools-version:6.2
import PackageDescription

// A throwaway spike that ships nothing: it measures on a Mac whether a process signed ad hoc
// with the hardened runtime and no entitlement, holding Accessibility and nothing else, can
// see the banners that Notification Center draws and read their title and text quickly
// enough, and whether the notification database can be opened without Full Disk Access
// (opened and closed, never read). It builds with the Command Line Tools alone and is not
// part of holzBar.app, the root test package or the Xcode project. No dependency, no network,
// no private API.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "NotificationsProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "NotificationProbeCore",
            swiftSettings: settings
        ),
        .executableTarget(
            name: "notifications-probe",
            dependencies: ["NotificationProbeCore"],
            swiftSettings: settings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "NotificationProbeCoreTests",
            dependencies: ["NotificationProbeCore"],
            swiftSettings: settings
        ),
    ]
)
