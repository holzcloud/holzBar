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
  AboutUpdateCommands
  AccessoryAlertOptions
  AccessoryBattery
  AccessoryDevice
  AccessoryLowBatteryGate
  AccessoryRefreshPolicy
  AccessoryTracker
  AgentRestartBreaker
  AlertNotificationPlan
  AlertRequestPlan
  AlertSeverity
  AppearanceMoods
  AppleItemReplacement
  AppVersion
  AudioOutputList
  AutomationEngine
  AutomationRule
  AXSnapshot
  BarClickTrace
  BatteryGlyph
  BatteryLevel
  BuiltInItem
  CalendarEvent
  CalendarReadFreshness
  CalendarSelection
  ClickPairing
  ClockClickPolicy
  ClosedHubWork
  ClosedNotchHeight
  CommandDragSection
  ConnectedDeviceList
  ControlCenterControl
  ControlItemOrder
  CountdownSchedule
  CPUClusters
  DDCCapabilities
  DDCDisplayMatch
  DDCFailurePolicy
  DDCLevel
  DDCPacket
  DDCRegistryPairing
  DDCReply
  DDCWakeGate
  DDCWriteCoalescer
  Defaults
  DesignTokens
  DiagnosticsReport
  DisplayBehavior
  DisplayControlsLevel
  DisplayControlsOrder
  DisplayCutout
  DividerPlausibility
  DockBadgeSettings
  DockIconPolicy
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
  HubContext
  HubIslandPhase
  HubLiveState
  HubModuleLifecycle
  HubModuleRow
  HubPin
  HubScrollGesture
  HubStatusPills
  HubTabStrip
  ImportBackupRecord
  IndicatorPolicy
  InputMonitors
  InputSourceLabel
  InterfaceWindowRule
  ItemCategory
  ItemChangeCadence
  ItemClassifier
  ItemIdentity
  ItemOpenOrigin
  ItemOrder
  ItemPlaceholder
  ItemRuleMemory
  ItemSpacingAvailability
  ItemTimer
  LayoutDraft
  LayoutList
  LayoutProfile
  LayoutProfileList
  LayoutSnapshot
  LegacyRevealRules
  LiveActivity
  LiveActivityItem
  MenuBarAnchor
  MenuBarBackendKind
  MenuBarDragDecider
  MenuBarFit
  MenuBarIconChoice
  MenuBarDrop
  MenuBarPills
  MediaKeyPress
  MeetingLinks
  MenuBarStyleOptions
  ModuleCatalog
  MoveBackoff
  MoveNeighbourCheck
  NewAppQuestion
  NextEvents
  NotchHubDisplays
  NotchHubGeometry
  NotchHubPolicy
  NotificationBannerParser
  NotificationLog
  NotificationQueue
  NotShownApps
  NowPlayingModel
  NowPlayingPayload
  NowPlayingPlayers
  NowPlayingRemoteLaunch
  NowPlayingRemoteMessage
  NowPlayingTrack
  OnboardingPolicy
  OpenMenuWait
  OutputVolumePlan
  OverflowAutoMove
  OwnBundle
  PauseState
  PermissionListing
  PinnedSystemItems
  PlaybackClock
  PreviousAppImport
  PrivateFeatureGate
  ReadoutFormat
  ReadoutHistory
  ReadoutLedger
  ReadoutTiles
  ReadoutValues
  ReopenGate
  ReorderDrag
  RevealAnimationPolicy
  RevealAnimationSchedule
  RevealAnimationStyle
  RevealGate
  RevealOwnership
  RevealStepRunner
  ScriptGate
  ScriptLaunch
  ScriptOutput
  ScriptStorage
  SecondaryMenuOwnership
  SettingsPaneID
  SettingsSchema
  SettingsSearch
  SharedProfile
  ShelfAlwaysHiddenFold
  ShelfClosedApps
  ShelfContents
  ShelfDrop
  ShelfFind
  ShelfFindRanking
  ShortcutLink
  SoftwareDimming
  SystemActivity
  ThresholdEvaluator
  ThresholdRule
  TimerBoard
  TimerFinishSound
  TimerInput
  TimerLiveActivities
  UndoHistory
  UngovernedItemOwners
  URLCommand
  URLPrompt
  VolumeSteps
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
  AboutUpdateCommandsTests
  AccessoryAlertOptionsTests
  AccessoryBatteryTests
  AccessoryDeviceTests
  AccessoryLowBatteryGateTests
  AccessoryRefreshPolicyTests
  AccessoryTrackerTests
  AgentRestartBreakerTests
  AlertNotificationPlanTests
  AlertRequestPlanTests
  AlertSeverityTests
  AppearanceMoodsTests
  AppleItemReplacementTests
  AppVersionTests
  AudioOutputListTests
  AutomationEngineTests
  AXSnapshotTests
  BarClickTraceTests
  BatteryGlyphTests
  BatteryLevelTests
  BuiltInItemTests
  CalendarEventTests
  CalendarReadFreshnessTests
  CalendarSelectionTests
  ClickPairingTests
  ClockClickPolicyTests
  ClosedHubWorkTests
  ClosedNotchHeightTests
  CommandDragSectionTests
  ConnectedDeviceListTests
  ControlCenterControlTests
  ControlItemOrderTests
  CountdownScheduleTests
  CPUClustersTests
  DDCCapabilitiesTests
  DDCDisplayMatchTests
  DDCFailurePolicyTests
  DDCLevelTests
  DDCPacketTests
  DDCRegistryPairingTests
  DDCReplyTests
  DDCWakeGateTests
  DDCWriteCoalescerTests
  DefaultsKeyNamesTests
  DesignTokensTests
  DiagnosticsReportTests
  DisplayBehaviorTests
  DisplayControlsLevelTests
  DisplayControlsOrderTests
  DisplayCutoutTests
  DividerPlausibilityTests
  DockBadgeSettingsTests
  DockIconPolicyTests
  DownloadScanTests
  DownloadTrackerTests
  FileDragWatchTests
  FileStashTests
  FocusFilterBindingTests
  HiddenItemCountTests
  HolzBarShelfPlacementTests
  HolzBarShelfStyleTests
  HubActivityBoardTests
  HubContextTests
  HubIslandPhaseTests
  HubLiveStateTests
  HubModuleLifecycleTests
  HubModuleRowTests
  HubPinTests
  HubScrollGestureTests
  HubStatusPillsTests
  HubTabStripTests
  IndicatorPolicyTests
  InputMonitorsTests
  InputSourceLabelTests
  InterfaceWindowRuleTests
  ItemCategoryTests
  ItemChangeCadenceTests
  ItemClassifierTests
  ItemIdentityTests
  ItemOrderTests
  ItemPlaceholderTests
  ItemRuleMemoryTests
  ItemSpacingAvailabilityTests
  ItemTimerTests
  LayoutDraftTests
  LayoutListTests
  LayoutProfileListTests
  LayoutProfileTests
  LayoutSnapshotTests
  LegacyRevealRulesTests
  LiveActivityItemTests
  MenuBarAnchorTests
  MenuBarDragDeciderTests
  MenuBarFitTests
  MenuBarIconChoiceTests
  MenuBarDropTests
  MenuBarPillsTests
  MediaKeyPressTests
  MeetingLinksTests
  MenuBarStyleOptionsTests
  ModuleCatalogTests
  MoveBackoffTests
  MoveNeighbourCheckTests
  NewAppQuestionTests
  NextEventsTests
  NotchHubDisplaysTests
  NotchHubGeometryTests
  NotchHubPolicyTests
  NotificationBannerParserTests
  NotificationLogTests
  NotificationQueueTests
  NotShownAppsTests
  NowPlayingModelTests
  NowPlayingPayloadTests
  NowPlayingPlayersTests
  NowPlayingRemoteLaunchTests
  NowPlayingRemoteMessageTests
  OnboardingPolicyTests
  OpenMenuWaitTests
  OutputVolumePlanTests
  OverflowAutoMoveTests
  OwnBundleTests
  PauseStateTests
  PermissionListingTests
  PinnedSystemItemsTests
  PlaybackClockTests
  PreviousAppImportTests
  PrivateFeatureGateTests
  ReadoutFormatTests
  ReadoutHistoryTests
  ReadoutLedgerTests
  ReadoutTilesTests
  ReadoutValuesTests
  ReopenGateTests
  ReorderDragTests
  RevealAnimationPolicyTests
  RevealAnimationScheduleTests
  RevealAnimationStyleTests
  RevealGateTests
  RevealOwnershipTests
  RevealStepRunnerTests
  ScriptGateTests
  ScriptLaunchTests
  ScriptOutputTests
  ScriptStorageTests
  SecondaryMenuOwnershipTests
  SettingsPaneIDTests
  SettingsSchemaTests
  SettingsSearchTests
  SharedProfileTests
  ShelfAlwaysHiddenFoldTests
  ShelfClosedAppsTests
  ShelfContentsTests
  ShelfDropTests
  ShelfFindTests
  ShortcutLinkTests
  SoftwareDimmingTests
  SystemActivityTests
  ThresholdEvaluatorTests
  ThresholdRuleTests
  TimerBoardTests
  TimerFinishSoundTests
  TimerInputTests
  TimerLiveActivitiesTests
  UndoHistoryTests
  UngovernedItemOwnersTests
  URLCommandTests
  URLPromptTests
  VolumeStepsTests
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
