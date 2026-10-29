//
//  CalendarBodyView.swift
//  holzBar
//

import SwiftUI

/// The Calendar tab: what is on now and the next events of today and tomorrow, each with its
/// calendar's colour and, when the event has a meeting link that can be joined, a Join button;
/// or a sentence that says why there is nothing to show, with the way forward.
struct CalendarBodyView: View {
    let runtime: CalendarRuntime
    let host: any HubHost

    var body: some View {
        Group {
            switch runtime.authorization {
            case .granted: list
            case .notDetermined: missingAccess("Calendar access is needed", button: "Allow Calendar Access")
            case .denied, .restricted: missingAccess("Calendar access is off", button: "Open System Settings")
            case .writeOnly: missingAccess("holzBar needs full access to read events", button: "Open System Settings")
            }
        }
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if runtime.rows.isEmpty {
            Text("No events today or tomorrow")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: HolzBarTheme.Spacing.xs) {
                    ForEach(runtime.rows) { model in
                        row(model)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ model: CalendarRowModel) -> some View {
        let event = model.row.event
        return HStack(spacing: HolzBarTheme.Spacing.sm) {
            CalendarColorDot(color: event.calendarColor)
            when(model.row)
                .font(HolzBarTheme.Typography.callout.monospacedDigit())
                .foregroundStyle(model.row.phase == .happening ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(verbatim: event.title.isEmpty ? String(localized: "Untitled") : event.title)
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let link = model.link {
                joinControl(link, isJoinable: model.isJoinable)
            }
            if model.row.phase != .allDay {
                Text(event.end, style: .time)
                    .font(HolzBarTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Now", the start time, or "All day".
    @ViewBuilder
    private func when(_ row: NextEvents.Row) -> some View {
        switch row.phase {
        case .happening: Text("Now")
        case .upcoming: Text(row.event.start, style: .time)
        case .allDay: Text("All day")
        }
    }

    /// The Join button while the link can be joined, else the service name as quiet text. The
    /// link opens only on a click.
    @ViewBuilder
    private func joinControl(_ link: MeetingLink, isJoinable: Bool) -> some View {
        if isJoinable {
            Button("Join") {
                runtime.join(link, host: host)
            }
            .buttonStyle(.borderedProminent)
            .tint(HolzBarTheme.Palette.accent)
            .controlSize(.small)
            .accessibilityLabel("Join the meeting")
            .help(Text(verbatim: serviceName(of: link)))
        } else {
            Text(verbatim: serviceName(of: link))
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textTertiary)
        }
    }

    /// The service's own name, which is the same in every language; for a link on another
    /// site, its host.
    private func serviceName(of link: MeetingLink) -> String {
        switch link.service {
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .webex: "Webex"
        case .faceTime: "FaceTime"
        case .other: link.url.host() ?? ""
        }
    }

    // MARK: Missing access

    /// A sentence and a button. Nothing asks by itself: the button is the only way.
    private func missingAccess(_ message: LocalizedStringKey, button: LocalizedStringKey) -> some View {
        VStack(spacing: HolzBarTheme.Spacing.sm) {
            Text(message)
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            Button(button) {
                runtime.allowAccess()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
