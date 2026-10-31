// swift-tools-version:6.2
import PackageDescription

// A throwaway spike that ships nothing: it measures on a Mac which public source tells holzBar
// what plays (the playback notifications of Apple Music and Spotify), whether a posted media
// key controls playback, whether artwork can be read from a song's own file, and (from Task 2
// on) whether the private MediaRemote route works on this macOS. It builds with the Command
// Line Tools alone and is not part of holzBar.app, the root test package or the Xcode project.
// No dependency, no network.
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "NowPlayingProbe",
    platforms: [.macOS(.v14)],
    products: [
        // The same code as RemoteProbeLib, built as a dynamic library for /usr/bin/perl to load.
        .library(name: "RemoteProbeDylib", type: .dynamic, targets: ["RemoteProbeLib"]),
    ],
    targets: [
        .target(
            name: "NowPlayingProbeCore",
            swiftSettings: settings
        ),
        .target(
            name: "RemoteProbeLib",
            swiftSettings: settings
        ),
        .executableTarget(
            name: "now-playing-probe",
            dependencies: ["NowPlayingProbeCore", "RemoteProbeLib"],
            swiftSettings: settings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ImageIO"),
            ]
        ),
        .testTarget(
            name: "NowPlayingProbeCoreTests",
            dependencies: ["NowPlayingProbeCore"],
            swiftSettings: settings
        ),
    ]
)
