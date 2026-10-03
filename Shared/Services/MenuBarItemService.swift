//
//  MenuBarItemService.swift
//  Shared
//

import Foundation

nonisolated enum MenuBarItemService {
    static let name = "com.holzcloud.holzBar.MenuBarItemService"

    /// The signing identifier of holzBar, the only app the service answers.
    ///
    /// Xcode signs with the bundle identifier. The build checks that the app's
    /// bundle identifier is `name` without `.MenuBarItemService`.
    static let appIdentifier = "com.holzcloud.holzBar"
}

nonisolated extension MenuBarItemService {
    nonisolated enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    nonisolated enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
