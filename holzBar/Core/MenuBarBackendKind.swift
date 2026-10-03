//
//  MenuBarBackendKind.swift
//  holzBar
//

import Foundation

/// The way holzBar reads, moves and clicks menu bar items, which depends on the
/// macOS generation.
///
/// - Before macOS 26, every item is a WindowServer window, owned by the process
///   that created it: the window list says everything.
/// - On macOS 26, Control Center owns every item window, so the process behind an
///   item comes from the menu bar item service (Accessibility, in the XPC service).
/// - From macOS 27, MenuBarAgent draws the items without windows; they are read,
///   hit tested and clicked through Accessibility, and they cannot be moved.
nonisolated enum MenuBarBackendKind: Equatable, Sendable {
    /// macOS 14 and 15: the window list.
    case windowList
    /// macOS 26: the window list, with source processes from the item service.
    case service26
    /// macOS 27 and later: Accessibility.
    case accessibility27

    /// The backend for the given major macOS version.
    init(majorVersion: Int) {
        switch majorVersion {
        case ..<26:
            self = .windowList
        case 26:
            self = .service26
        default:
            self = .accessibility27
        }
    }

    /// The backend for the running macOS.
    static var current: MenuBarBackendKind {
        MenuBarBackendKind(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}
