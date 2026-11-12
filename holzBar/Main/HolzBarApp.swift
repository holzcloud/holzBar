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
        WhatsNewWindow(appState: appDelegate.appState)
        OnboardingWindow(appState: appDelegate.appState)
        ScreenRecordingOfferWindow(appState: appDelegate.appState)
    }
}
