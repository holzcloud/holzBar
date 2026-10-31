//
//  NotificationsBodyView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Notifications tab: the banners macOS showed while the hub was on, newest first.
///
/// The view draws what the runtime holds as plain text, never as markup or a link, and holds
/// nothing itself. When the module cannot read, a quiet line says why.
struct NotificationsBodyView: View {
    let runtime: NotificationsRuntime

    private static let iconSize = CGFloat(24)

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            if runtime.log.records.isEmpty {
                EmptyState(
                    systemImage: "bell.badge",
                    title: Text("No notifications yet"),
                    message: Text("Banners that macOS shows appear here while the hub is on. Nothing is stored.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                        ForEach(runtime.log.records) { record in
                            row(record)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, HolzBarTheme.Spacing.xxs)
                }
            }
            if let reason {
                reason
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    /// Why the module is not reading, in a caption.
    private var reason: Text? {
        switch runtime.readerState {
        case .registering, .running: nil
        case .noPermission: Text("Not reading: Accessibility is off")
        case .notificationCenterMissing: Text("Not reading: Notification Center is not running")
        case .unavailable: Text("Not reading: macOS did not allow it")
        }
    }

    private func row(_ record: NotificationRecord) -> some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.sm) {
            icon(for: record.app)
                .frame(width: Self.iconSize, height: Self.iconSize)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.hairline) {
                if let title = record.title {
                    Text(verbatim: title)
                        .font(HolzBarTheme.Typography.callout)
                        .foregroundStyle(HolzBarTheme.Palette.text)
                        .lineLimit(1)
                }
                if let body = record.body {
                    Text(verbatim: body)
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text(record.received, style: .relative)
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .monospacedDigit()
        }
    }

    /// The icon of the app among the running ones, found by its name, else a bell.
    @ViewBuilder
    private func icon(for app: String?) -> some View {
        if let app, let icon = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == app })?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "bell")
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .accessibilityHidden(true)
        }
    }
}
