//
//  DiagnosticsCollector.swift
//  holzBar
//

import AppKit
import ServiceManagement

/// Gathers the facts of a bug report from the running app. Each fact is a version, an
/// identifier of the system or a count; names the user chose are never read.
@MainActor
enum DiagnosticsCollector {
    static func collect(from appState: AppState) -> DiagnosticsInput {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let cache = appState.itemManager.itemCache
        func count(_ section: MenuBarSection.Name) -> Int {
            cache[section].filter { !$0.isControlItem }.count
        }
        return DiagnosticsInput(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            macOSBuild: sysctlString("kern.osversion"),
            modelIdentifier: sysctlString("hw.model"),
            architecture: architecture,
            backend: backendName(majorVersion: version.majorVersion),
            displayCount: NSScreen.screens.count,
            displaysWithNotch: NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count,
            accessibilityGranted: appState.permissions.accessibility.hasPermission,
            screenRecordingGranted: ScreenRecordingAccess.isGranted(appState),
            launchesAtLogin: SMAppService.mainApp.status == .enabled,
            visibleItems: count(.visible),
            hiddenItems: count(.hidden),
            alwaysHiddenItems: count(.alwaysHidden),
            profileCount: appState.profiles.profiles.count,
            groupCount: appState.itemGroups.groups.count,
            spacerCount: appState.spacers.count,
            automationRuleCount: appState.automation.rules.count,
            snapshotCount: appState.snapshots.snapshots.count,
            nativeOverflow: nativeOverflowWord(appState),
            appleItems: appleItemsWord(appState),
            lastDrop: lastDropWords(appState),
            lastCommandDrag: lastCommandDragWords(appState),
            hiding: hidingWords(appState),
            lastShelfClick: lastShelfClickWords(),
            shelf: shelfWords(appState),
            accessoryBattery: accessoryBatteryWord(appState),
            barClicks: BarClickLog.trace.lines
        )
    }

    /// Whether the undocumented battery call of Accessory alerts works on this Mac, in one of
    /// three fixed words; nothing while the module is off. It reads no device and no name.
    private static func accessoryBatteryWord(_ appState: AppState) -> String {
        guard appState.modules.isEnabled(AccessoryAlertsRuntime.identifier) else {
            return ""
        }
        guard AccessoryAlertsSettings.readsBattery() else {
            return "off"
        }
        return AccessoryBatterySource.isAvailable ? "available" : "not available"
    }

    /// The last click on a Shelf tile in fixed words; nothing before macOS 27.
    private static func lastShelfClickWords() -> String {
        guard #available(macOS 27.0, *) else {
            return ""
        }
        return ItemClicker27.lastClick
    }

    /// The last drop of Drag in the Menu Bar, in the fixed words the controller wrote; nothing
    /// while the module is off or before macOS 27.
    private static func lastDropWords(_ appState: AppState) -> String {
        guard MenuBarBackendKind.current == .accessibility27, appState.modules.isEnabled(MenuBarDragController.moduleID) else {
            return ""
        }
        return MenuBarDragController.lastDrop
    }

    /// The last Command-drag that could set a section, in the fixed words the feature wrote;
    /// nothing while its switch is off or before macOS 27.
    private static func lastCommandDragWords(_ appState: AppState) -> String {
        guard #available(macOS 27.0, *), MenuBarBackendKind.current == .accessibility27,
              appState.settings.general.commandDragSetsSection else {
            return ""
        }
        return CommandDragSection27.lastSummary
    }

    /// What the hiding fixes of 1.0.5 did, in fixed words and counts: on macOS 27 the reveal
    /// state and the counters of the concealment, the item reads and the Accessibility scan;
    /// before macOS 27 the anchor of the last menu bar hit test and the icons put back. It
    /// reads counters only, never an item or an app.
    private static func hidingWords(_ appState: AppState) -> String {
        let itemManager = appState.itemManager
        if #available(macOS 27.0, *), MenuBarBackendKind.current == .accessibility27 {
            let concealer = appState.concealer27
            let reveal = switch concealer.revealState(appState) {
            case .allHidden: "all hidden"
            case .hiddenRevealed: "hidden revealed"
            case .allRevealed: "all revealed"
            }
            return DiagnosticsReport.hidingSummary27(
                reveal: reveal,
                agentRestarts: concealer.agentRestarts,
                lateAllowlist: concealer.lateAllowlistRefreshes,
                youngRetries: MenuBarItemProvider27.youngRetries,
                forcedReads: itemManager.forcedItemReads,
                heldBack: itemManager.heldBackItemReads,
                notchRechecks: concealer.notchRechecks
            )
        }
        return DiagnosticsReport.hidingSummaryBefore27(
            anchor: appState.hidEventManager.lastMenuBarAnchor.rawValue,
            iconPutBack: itemManager.iconPutBack
        )
    }

    /// The Shelf's style and location in fixed words; nothing while the Shelf is off.
    private static func shelfWords(_ appState: AppState) -> String {
        let general = appState.settings.general
        guard general.useShelf else {
            return ""
        }
        let style = switch general.shelfStyle {
        case .attached: "attached"
        case .floating: "floating"
        }
        let location = switch general.shelfLocation {
        case .dynamic: "dynamic"
        case .mousePointer: "mouse pointer"
        case .holzBarIcon: "holzBar icon"
        case .screenEdge: "screen edge"
        }
        return "\(style), \(location)"
    }

    /// The state of the Apple Items module in fixed words and numbers; nothing before macOS 27.
    private static func appleItemsWord(_ appState: AppState) -> String {
        guard AppleItems.isSupported else {
            return ""
        }
        guard appState.modules.isEnabled(AppleItems.moduleID) else {
            return "off"
        }
        let appleItems = appState.appleItems
        let applied = appleItems.concealedSystemItems(in: appState).isEmpty ? "no" : "yes"
        return "on, hidden \(appleItems.hiddenSystemItems.count), applied \(applied), replaced \(appleItems.replacements.count)"
    }

    /// The state of macOS 27's own overflow control from the last read; nothing before macOS 27.
    private static func nativeOverflowWord(_ appState: AppState) -> String {
        guard #available(macOS 27.0, *) else {
            return ""
        }
        return appState.concealer27.nativeOverflow.state.rawValue
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func backendName(majorVersion: Int) -> String {
        switch MenuBarBackendKind(majorVersion: majorVersion) {
        case .windowList: "window list (macOS 14 and 15)"
        case .service26: "service (macOS 26)"
        case .accessibility27: "accessibility (macOS 27)"
        }
    }

    /// A string the kernel reports, such as the model identifier.
    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
    }
}
