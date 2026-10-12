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
            snapshotCount: appState.snapshots.snapshots.count
        )
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
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }
}
