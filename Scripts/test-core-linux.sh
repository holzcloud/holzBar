#!/bin/bash
#
# Runs the unit tests of holzBar's pure logic on Linux, without a Mac, or on a Mac as a quick local
# check.
#
# Only the files of holzBar/Core that need nothing but Foundation compile on Linux; they are
# listed below with their tests and built as a throwaway package with the app's concurrency
# settings. On Linux this proves they build with swift-corelibs-foundation. On a Mac (Darwin) the
# same lists run against Apple's Foundation: a quick check, not a proof of the Linux build. The
# app itself (SwiftUI, AppKit) needs macOS and is built by CI.
#
# Needs a Swift 6.4 toolchain on the PATH (Linux: https://www.swift.org/install/linux/).
# Add a new Core file and its test to the lists when they need only Foundation.
# Pass arguments to swift test, for example --filter ShelfFindTests.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

sources=(
  AccessoryAlertOptions
  AccessoryBattery
  AccessoryDevice
  AccessoryLowBatteryGate
  AccessoryRefreshPolicy
  AccessoryTracker
  AppearanceMoods
  AppleItemReplacement
  AppVersion
  AutomationEngine
  AutomationRule
  AXSnapshot
  BarClickTrace
  BatteryLevel
  BuiltInItem
  CalendarEvent
  CalendarSelection
  ClockClickPolicy
  ControlCenterControl
  Defaults
  DesignTokens
  DiagnosticsReport
  DisplayBehavior
  DisplayControlsLevel
  DividerPlausibility
  DownloadScan
  DownloadTracker
  FileDragWatch
  FileStash
  FocusFilterBinding
  FuzzyMatch
  HiddenItemCount
  HolzBarShelfPlacement
  HolzBarShelfStyle
  HubActivityBoard
  HubModuleLifecycle
  HubTabStrip
  ItemCategory
  ItemClassifier
  ItemIdentity
  ItemOpenOrigin
  ItemOrder
  ItemPlaceholder
  ItemRuleMemory
  ItemTimer
  LayoutDraft
  LayoutProfile
  LayoutProfileList
  LayoutSnapshot
  LegacyRevealRules
  LiveActivity
  MenuBarBackendKind
  MenuBarDragDecider
  MenuBarIconChoice
  MenuBarDrop
  MenuBarPills
  MeetingLinks
  MenuBarStyleOptions
  ModuleCatalog
  MoveBackoff
  NextEvents
  NotchHubDisplays
  NotchHubGeometry
  NotchHubPolicy
  NotificationBannerParser
  NotificationLog
  NowPlayingModel
  NowPlayingPayload
  NowPlayingPlayers
  NowPlayingRemoteLaunch
  NowPlayingRemoteMessage
  NowPlayingTrack
  OutputVolumePlan
  OwnBundle
  PinnedSystemItems
  PlaybackClock
  PrivateFeatureGate
  ReorderDrag
  RevealAnimationPolicy
  RevealAnimationSchedule
  RevealAnimationStyle
  RevealGate
  RevealStepRunner
  ScriptGate
  ScriptLaunch
  ScriptOutput
  ScriptStorage
  SettingsSchema
  SharedProfile
  ShelfAlwaysHiddenFold
  ShelfClosedApps
  ShelfContents
  ShelfDrop
  ShelfFind
  ShelfFindRanking
  ShortcutLink
  SystemActivity
  TimerBoard
  TimerFinishSound
  TimerInput
  UngovernedItemOwners
  URLCommand
  URLPrompt
  WidgetDefinition
  WidgetFormat
  WidgetReadings
  WidgetRefreshPolicy
  WidgetScriptSharing
  WhatsNewGrouping
  WhatsNewHistory
  WhatsNewPolicy
  WhatsNewRelease
  ZenMode
)
tests=(
  AccessoryAlertOptionsTests
  AccessoryBatteryTests
  AccessoryDeviceTests
  AccessoryLowBatteryGateTests
  AccessoryRefreshPolicyTests
  AccessoryTrackerTests
  AppearanceMoodsTests
  AppleItemReplacementTests
  AppVersionTests
  AutomationEngineTests
  AXSnapshotTests
  BarClickTraceTests
  BatteryLevelTests
  BuiltInItemTests
  CalendarSelectionTests
  ClockClickPolicyTests
  ControlCenterControlTests
  DesignTokensTests
  DiagnosticsReportTests
  DisplayBehaviorTests
  DisplayControlsLevelTests
  DividerPlausibilityTests
  DownloadScanTests
  DownloadTrackerTests
  FileDragWatchTests
  FileStashTests
  FocusFilterBindingTests
  HiddenItemCountTests
  HolzBarShelfPlacementTests
  HolzBarShelfStyleTests
  HubActivityBoardTests
  HubModuleLifecycleTests
  HubTabStripTests
  ItemCategoryTests
  ItemClassifierTests
  ItemIdentityTests
  ItemOrderTests
  ItemPlaceholderTests
  ItemRuleMemoryTests
  ItemTimerTests
  LayoutDraftTests
  LayoutProfileListTests
  LayoutSnapshotTests
  LegacyRevealRulesTests
  MenuBarDragDeciderTests
  MenuBarIconChoiceTests
  MenuBarDropTests
  MenuBarPillsTests
  MeetingLinksTests
  MenuBarStyleOptionsTests
  ModuleCatalogTests
  MoveBackoffTests
  NextEventsTests
  NotchHubDisplaysTests
  NotchHubGeometryTests
  NotchHubPolicyTests
  NotificationBannerParserTests
  NotificationLogTests
  NowPlayingModelTests
  NowPlayingPayloadTests
  NowPlayingPlayersTests
  NowPlayingRemoteLaunchTests
  NowPlayingRemoteMessageTests
  OutputVolumePlanTests
  OwnBundleTests
  PinnedSystemItemsTests
  PlaybackClockTests
  PrivateFeatureGateTests
  ReorderDragTests
  RevealAnimationPolicyTests
  RevealAnimationScheduleTests
  RevealAnimationStyleTests
  RevealGateTests
  RevealStepRunnerTests
  ScriptGateTests
  ScriptLaunchTests
  ScriptOutputTests
  ScriptStorageTests
  SettingsSchemaTests
  SharedProfileTests
  ShelfAlwaysHiddenFoldTests
  ShelfClosedAppsTests
  ShelfContentsTests
  ShelfDropTests
  ShelfFindTests
  ShortcutLinkTests
  SystemActivityTests
  TimerBoardTests
  TimerFinishSoundTests
  TimerInputTests
  UngovernedItemOwnersTests
  URLCommandTests
  URLPromptTests
  WidgetDefinitionTests
  WidgetFormatTests
  WidgetReadingsTests
  WidgetRefreshPolicyTests
  WidgetScriptSharingTests
  WhatsNewGroupingTests
  WhatsNewHistoryTests
  WhatsNewPolicyTests
  ZenModeTests
)

mkdir -p "$scratch/Sources/HolzBarCore" "$scratch/Tests/HolzBarCoreTests"
for name in "${sources[@]}"; do
  ln -s "$root/holzBar/Core/$name.swift" "$scratch/Sources/HolzBarCore/$name.swift"
done
for name in "${tests[@]}"; do
  ln -s "$root/Tests/HolzBarCoreTests/$name.swift" "$scratch/Tests/HolzBarCoreTests/$name.swift"
done

platforms=""
if [ "$(uname)" != "Darwin" ]; then
  # swift-corelibs-foundation has no Core Foundation type identifiers; SettingsSchema uses them to
  # tell a Boolean from a number. On macOS, Foundation re-exports Core Foundation, so the shim
  # would clash with it.
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
else
  # The app's deployment target; Duration, ContinuousClock and regex literals need macOS 13.
  platforms=$'\n    platforms: [.macOS(.v14)],'
fi

# The heredoc is unquoted so that ${platforms} expands; the body has no other dollar sign.
cat > "$scratch/Package.swift" <<SWIFT
// swift-tools-version:6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let package = Package(
    name: "LinuxCore",${platforms}
    targets: [
        .target(name: "HolzBarCore", path: "Sources/HolzBarCore", swiftSettings: settings + [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "HolzBarCoreTests", dependencies: ["HolzBarCore"], path: "Tests/HolzBarCoreTests", swiftSettings: settings),
    ]
)
SWIFT

cd "$scratch"
swift test "$@"
