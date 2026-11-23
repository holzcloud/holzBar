//
//  NotificationsBodyView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The Notifications tab: the banners macOS showed while the hub was on, newest first.
///
/// The view draws what the runtime holds as plain text, never as markup or a link. Each row can be
/// removed, or its app excluded for good; Clear all erases the list. When the module cannot read,
/// a quiet line says why.
///
/// A notification not seen yet carries a small accent dot before its icon; everything listed
/// counts as seen when the tab goes away. A row expands in place to a card while the pointer rests
/// on it, while it has keyboard focus or while the VoiceOver cursor is on it, one at a time. What
/// the card shows is view state only: nothing of it is stored in the runtime.
///
/// The newest unseen notification is the front card: it stands first in the list, already
/// expanded, and removing it brings the next unseen one to the front. With none unseen the tab is
/// the plain list.
struct NotificationsBodyView: View {
    let runtime: NotificationsRuntime

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// The row the pointer has rested on long enough, or `nil`.
    @State private var hoveredID: NotificationRecord.ID?
    /// The wait before a hovered row expands; one at a time, cancelled when the pointer leaves.
    @State private var dwellTask: Task<Void, Never>?
    @FocusState private var focus: FocusTarget?
    @AccessibilityFocusState private var spokenID: NotificationRecord.ID?

    private static let iconSize = HolzBarTheme.minimumTargetSize
    private static let cardIconSize: CGFloat = 28
    private static let unseenDotSize: CGFloat = 6

    /// Where keyboard focus can be: the row itself or one of its two buttons.
    private enum FocusTarget: Hashable {
        case row(NotificationRecord.ID)
        case exclude(NotificationRecord.ID)
        case remove(NotificationRecord.ID)

        var recordID: NotificationRecord.ID {
            switch self {
            case .row(let id), .exclude(let id), .remove(let id): id
            }
        }
    }

    /// The row that shows as a card: the one the pointer rests on, else the one with keyboard
    /// focus (on it or on one of its buttons), else the one the VoiceOver cursor is on.
    private var expandedID: NotificationRecord.ID? {
        hoveredID ?? focus?.recordID ?? spokenID
    }

    /// The newest unseen notification, when the log still holds it: the front card.
    private var frontRecord: NotificationRecord? {
        guard let id = runtime.queue.front else {
            return nil
        }
        return runtime.log.records.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            if runtime.log.records.isEmpty {
                EmptyState(
                    systemImage: "bell.badge",
                    title: Text("No notifications yet"),
                    message: Text("Banners that macOS shows appear here while the hub is on. Nothing is stored."),
                    isCompact: true
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                        let front = frontRecord
                        if let front {
                            row(front, isFront: true)
                        }
                        ForEach(runtime.log.records.filter { $0.id != front?.id }) { record in
                            row(record, isFront: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, HolzBarTheme.Spacing.xxs)
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear {
            dwellTask?.cancel()
            runtime.tabDidDisappear()
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

    private func row(_ record: NotificationRecord, isFront: Bool) -> some View {
        let isUnseen = runtime.queue.isUnseen(record.id)
        return Group {
            if isFront || expandedID == record.id {
                card(record, isFront: isFront)
            } else {
                collapsedRow(record, isUnseen: isUnseen)
            }
        }
        .focusable()
        .focused($focus, equals: .row(record.id))
        .onHover { isInside in
            hoverDidChange(isInside, record: record)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenText(of: record, isUnseen: isUnseen, isFront: isFront)))
        .accessibilityFocused($spokenID, equals: record.id)
        .accessibilityAction(named: Text("Remove")) {
            remove(record.id, isFront: isFront)
        }
        .modifier(ExcludeAction(app: record.app) { app in
            runtime.exclude(app: app)
        })
    }

    private func collapsedRow(_ record: NotificationRecord, isUnseen: Bool) -> some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.sm) {
            if isUnseen {
                // The unseen marker, 8 pt before the icon; the row's spoken text says "new".
                Circle()
                    .fill(HolzBarTheme.Palette.accent)
                    .frame(width: Self.unseenDotSize, height: Self.unseenDotSize)
                    .padding(.top, (Self.iconSize - Self.unseenDotSize) / 2)
                    .padding(.trailing, HolzBarTheme.Spacing.xs - HolzBarTheme.Spacing.sm)
                    .accessibilityHidden(true)
            }
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
            age(of: record)
            buttons(for: record, isFront: false)
        }
    }

    /// The card a row expands to: the app icon, the app name with the Preview badge, the title
    /// (two lines), the text (three lines), the age and the two buttons. Every text is plain text,
    /// never markup or a link. It is at most ``DesignTokens/Indicator/cardMaximumHeight`` high and
    /// sits inside the tab's scroll, so the hub's height never changes.
    private func card(_ record: NotificationRecord, isFront: Bool) -> some View {
        let radius = CGFloat(DesignTokens.Hub.tileRadius)
        let fill = reduceTransparency ? DesignTokens.Hub.tileFillAlphaOpaque : DesignTokens.Hub.tileFillAlpha
        return HStack(alignment: .top, spacing: HolzBarTheme.Spacing.sm) {
            icon(for: record.app)
                .frame(width: Self.cardIconSize, height: Self.cardIconSize)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.hairline) {
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    if let app = record.app {
                        Text(verbatim: app)
                            .font(HolzBarTheme.Typography.caption)
                            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    PreviewBadge()
                    Spacer(minLength: 0)
                    age(of: record)
                    buttons(for: record, isFront: isFront)
                    if isFront, runtime.queue.extraCount > 0 {
                        queueCapsule(runtime.queue.extraCount)
                    }
                }
                if let title = record.title {
                    Text(verbatim: title)
                        .font(HolzBarTheme.Typography.body)
                        .foregroundStyle(HolzBarTheme.Palette.text)
                        .lineLimit(2)
                }
                if let body = record.body {
                    Text(verbatim: body)
                        .font(HolzBarTheme.Typography.callout)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(CGFloat(DesignTokens.Hub.tilePadding))
        .frame(maxWidth: .infinity, maxHeight: DesignTokens.Indicator.cardMaximumHeight, alignment: .topLeading)
        .background(.white.opacity(fill), in: HolzBarTheme.shape(radius))
        .overlay {
            HolzBarTheme.shape(radius)
                .stroke(.white.opacity(contrast == .increased ? 0.4 : 0.06), lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .clipShape(HolzBarTheme.shape(radius))
    }

    /// The `+N` capsule at the front card's top trailing corner: how many unseen notifications
    /// wait behind it. It shows a number only, never a title, an app or a text, and it keeps its
    /// width, so the header's app name gives way first.
    private func queueCapsule(_ count: Int) -> some View {
        Text(verbatim: "+\(count)")
            .font(HolzBarTheme.Hub.pillFont)
            .monospacedDigit()
            .foregroundStyle(contrast == .increased ? HolzBarTheme.Hub.pillText : HolzBarTheme.Hub.neutral)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(HolzBarTheme.Hub.pillFill, in: Capsule())
            .overlay {
                if contrast == .increased {
                    Capsule().stroke(HolzBarTheme.Hub.neutral)
                }
            }
            .layoutPriority(1)
            .accessibilityLabel(Text("+\(count) more"))
    }

    private func age(of record: NotificationRecord) -> some View {
        Text(record.received, style: .relative)
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .monospacedDigit()
    }

    /// The two buttons of a notification: never show its app again, and remove it.
    @ViewBuilder
    private func buttons(for record: NotificationRecord, isFront: Bool) -> some View {
        if let app = record.app {
            iconButton(
                "eye.slash",
                label: Text("Never show notifications from this app"),
                target: .exclude(record.id)
            ) {
                hoveredID = nil
                runtime.exclude(app: app)
            }
        }
        iconButton("xmark", label: Text("Remove"), target: .remove(record.id)) {
            remove(record.id, isFront: isFront)
        }
    }

    /// Removes a notification; the front card goes through ``NotificationsRuntime/dismissFront(_:)``,
    /// which brings the next unseen one to the front.
    private func remove(_ id: NotificationRecord.ID, isFront: Bool) {
        hoveredID = nil
        if isFront {
            runtime.dismissFront(id)
        } else {
            runtime.remove(id)
        }
    }

    // MARK: Hover

    /// Starts the wait before a row expands when the pointer arrives, and collapses the card when
    /// it leaves. The change is a 0.2 s smooth one, and none at all under Reduce Motion.
    private func hoverDidChange(_ isInside: Bool, record: NotificationRecord) {
        dwellTask?.cancel()
        dwellTask = nil
        if isInside {
            dwellTask = Task {
                try? await Task.sleep(for: .seconds(DesignTokens.Indicator.cardHoverDwell))
                guard !Task.isCancelled else {
                    return
                }
                setHovered(record.id)
            }
        } else if hoveredID == record.id {
            setHovered(nil)
        }
    }

    private func setHovered(_ id: NotificationRecord.ID?) {
        if reduceMotion {
            hoveredID = id
        } else {
            withAnimation(.smooth(duration: 0.2)) {
                hoveredID = id
            }
        }
    }

    /// A 24 pt button with a symbol.
    private func iconButton(
        _ systemImage: String,
        label: Text,
        target: FocusTarget,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focus, equals: target)
        .accessibilityLabel(label)
        .help(label)
    }

    /// What VoiceOver reads for a row: "new" for one not seen yet, the app, the title, the text,
    /// how long ago it came and, for the front card with more behind it, "+N more".
    private func spokenText(of record: NotificationRecord, isUnseen: Bool, isFront: Bool) -> String {
        let age = record.received.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
        let newWord: String? = isUnseen ? String(localized: "new") : nil
        let extra = runtime.queue.extraCount
        let moreWord: String? = isFront && extra > 0 ? String(localized: "+\(extra) more") : nil
        return [newWord, record.app, record.title, record.body, age, moreWord]
            .compactMap(\.self)
            .joined(separator: ", ")
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
