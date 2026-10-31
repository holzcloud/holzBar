//
//  NotificationsBodyView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Notifications tab: the banners macOS showed while the hub was on, newest first.
///
/// The view draws what the runtime holds as plain text, never as markup or a link, and holds
/// nothing itself. Each row can be removed, or its app excluded for good; Clear all erases the
/// list. When the module cannot read, a quiet line says why.
struct NotificationsBodyView: View {
    let runtime: NotificationsRuntime

    private static let iconSize = HolzBarTheme.minimumTargetSize

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
            footer
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
        .onAppear {
            runtime.markSeen()
        }
        .onChange(of: runtime.log.records.count) {
            // The tab is on screen, so a notification that arrives now is seen.
            runtime.markSeen()
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        let reason = reason
        if reason != nil || runtime.log.records.count >= 2 {
            HStack {
                if let reason {
                    reason
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                if runtime.log.records.count >= 2 {
                    Button("Clear all") {
                        runtime.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.accent)
                }
            }
        }
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

    // MARK: Rows

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
            if let app = record.app {
                iconButton("eye.slash", label: Text("Never show notifications from this app")) {
                    runtime.exclude(app: app)
                }
            }
            iconButton("xmark", label: Text("Remove")) {
                runtime.remove(record.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenText(of: record)))
        .accessibilityAction(named: Text("Remove")) {
            runtime.remove(record.id)
        }
        .modifier(ExcludeAction(app: record.app) { app in
            runtime.exclude(app: app)
        })
    }

    /// A 24 pt button with a symbol.
    private func iconButton(_ systemImage: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// What VoiceOver reads for a row: the app, the title, the text and how long ago it came.
    private func spokenText(of record: NotificationRecord) -> String {
        let age = record.received.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
        return [record.app, record.title, record.body, age].compactMap(\.self).joined(separator: ", ")
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

/// Adds the named VoiceOver action "Never show notifications from this app" to a row whose app
/// is known.
private struct ExcludeAction: ViewModifier {
    let app: String?
    let action: (String) -> Void

    func body(content: Content) -> some View {
        if let app {
            content.accessibilityAction(named: Text("Never show notifications from this app")) {
                action(app)
            }
        } else {
            content
        }
    }
}
