//
//  MenuBarItemService.swift
//  Shared
//

import Foundation

enum MenuBarItemService {
    static let name = "com.holzcloud.holzBar.MenuBarItemService"
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
