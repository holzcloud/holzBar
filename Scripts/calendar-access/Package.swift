// swift-tools-version:6.2
import PackageDescription

// A throwaway spike that ships nothing: it measures on a Mac whether an app signed with the
// hardened runtime can ask for and use Calendar access without an entitlement, and whether it
// can with `com.apple.security.personal-information.calendars`. It is built by
// `build-probe-app.sh` with the Command Line Tools alone and is not part of holzBar.app, the
// root test package or the Xcode project. No dependency, no network.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "CalendarAccessProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CalendarAccessCore",
            swiftSettings: settings
        ),
        .executableTarget(
            name: "calendar-access-probe",
            dependencies: ["CalendarAccessCore"],
            swiftSettings: settings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
            ]
        ),
        .testTarget(
            name: "CalendarAccessCoreTests",
            dependencies: ["CalendarAccessCore"],
            swiftSettings: settings
        ),
    ]
)
