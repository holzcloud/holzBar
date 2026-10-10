#!/bin/bash
#
# Runs the unit tests of holzBar's pure logic on Linux, without a Mac.
#
# Only the files of holzBar/Core that need nothing but Foundation compile on Linux; they are
# listed below with their tests and built as a throwaway package with the app's concurrency
# settings. The app itself (SwiftUI, AppKit) needs macOS and is built by CI.
#
# Needs a Swift 6.4 toolchain for Linux on the PATH (https://www.swift.org/install/linux/).
# Add a file to the lists when it and its tests need only Foundation.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

sources=(
  AutomationEngine AutomationRule BatteryLevel Defaults DesignTokens DiagnosticsReport FocusFilterBinding
  ItemClassifier ItemIdentity LayoutSnapshot LegacyRevealRules ModuleCatalog PinnedSystemItems RevealGate ScriptGate SettingsSchema SharedProfile URLCommand ZenMode
)
tests=(
  AutomationEngineTests BatteryLevelTests DesignTokensTests DiagnosticsReportTests FocusFilterBindingTests
  ItemClassifierTests LayoutSnapshotTests LegacyRevealRulesTests ModuleCatalogTests PinnedSystemItemsTests RevealGateTests ScriptGateTests SettingsSchemaTests SharedProfileTests URLCommandTests
)

mkdir -p "$scratch/Sources/HolzBarCore" "$scratch/Tests/HolzBarCoreTests"
for name in "${sources[@]}"; do
  ln -s "$root/holzBar/Core/$name.swift" "$scratch/Sources/HolzBarCore/$name.swift"
done
for name in "${tests[@]}"; do
  ln -s "$root/Tests/HolzBarCoreTests/$name.swift" "$scratch/Tests/HolzBarCoreTests/$name.swift"
done

# swift-corelibs-foundation has no Core Foundation type identifiers; SettingsSchema uses them to
# tell a Boolean from a number.
cat > "$scratch/Sources/HolzBarCore/LinuxShim.swift" <<'SWIFT'
import Foundation

typealias CFTypeID = UInt

nonisolated func CFBooleanGetTypeID() -> CFTypeID { 1 }

nonisolated func CFGetTypeID(_ object: AnyObject) -> CFTypeID {
    if let number = object as? NSNumber, String(cString: number.objCType) == "c" {
        return 1
    }
    return 0
}
SWIFT

cat > "$scratch/Package.swift" <<'SWIFT'
// swift-tools-version:6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let package = Package(
    name: "LinuxCore",
    targets: [
        .target(name: "HolzBarCore", path: "Sources/HolzBarCore", swiftSettings: settings + [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "HolzBarCoreTests", dependencies: ["HolzBarCore"], path: "Tests/HolzBarCoreTests", swiftSettings: settings),
    ]
)
SWIFT

cd "$scratch"
swift test "$@"
