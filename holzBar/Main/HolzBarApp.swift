//
//  HolzBarApp.swift
//  holzBar
//

import SwiftUI

@main
struct HolzBarApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
    }
}
