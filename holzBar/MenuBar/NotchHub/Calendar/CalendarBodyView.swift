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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The row whose details are open: one at a time, view state only.
    @State private var openID: CalendarRowModel.ID?

    /// The column of a detail line's symbol, and the width of an event's time column.
    private static let symbolColumn: CGFloat = 16
    private static let whenColumn: CGFloat = 64
    private static let dotColumn: CGFloat = 8

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        let isOpen = openID == model.id && hasDetails(model)
        return VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            header(model, isOpen: isOpen)
            if isOpen {
                detailLines(model)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The row's line: the colour, the time, the title, Join, the end time and, when there is
    /// something to show, the disclosure. A click outside Join and the disclosure opens or closes
    /// the details.
    private func header(_ model: CalendarRowModel, isOpen: Bool) -> some View {
        let event = model.row.event
        return HStack(spacing: HolzBarTheme.Spacing.sm) {
            CalendarColorDot(color: event.calendarColor)
            when(model.row)
                .font(HolzBarTheme.Typography.callout.monospacedDigit())
                .foregroundStyle(model.row.phase == .happening ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textSecondary)
                .frame(width: Self.whenColumn, alignment: .leading)
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
            if hasDetails(model) {
                disclosure(model, isOpen: isOpen)
            }
        }
        .background {
            // Behind the controls, so Join and the disclosure keep their own clicks.
            if hasDetails(model) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggle(model)
                    }
                    // The disclosure is the accessible way; this layer only widens the click.
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Details

    /// Whether the row has something to show beyond its line: a place, invitees, a meeting
    /// service or notes.
    private func hasDetails(_ model: CalendarRowModel) -> Bool {
        let event = model.row.event
        return place(of: event) != nil || attendees(of: event) != nil
            || model.link != nil || excerpt(of: event) != nil
    }

    /// The place, when there is one that is not only blank.
    private func place(of event: CalendarEvent) -> String? {
        guard let place = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty else {
            return nil
        }
        return place
    }

    /// The number of invitees, when it is above zero. Never a name.
    private func attendees(of event: CalendarEvent) -> Int? {
        guard let count = event.attendeeCount, count > 0 else {
            return nil
        }
        return count
    }

    /// The notes cut to the detail length (300 characters), when there are some that
    /// are not only blank. The row shows three lines of it.
    private func excerpt(of event: CalendarEvent) -> String? {
        guard let text = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return String(text.prefix(CalendarEvent.detailNotesLength))
    }

    /// The 10 pt chevron in a 24 pt target: down while closed, up while open.
    private func disclosure(_ model: CalendarRowModel, isOpen: Bool) -> some View {
        Button {
            toggle(model)
        } label: {
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(HolzBarTheme.Hub.chevronFont)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? Text("Hide details") : Text("Show details"))
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .help(isOpen ? Text("Hide details") : Text("Show details"))
    }

    /// Opens the row and closes any other; a second click closes it. No animation under Reduce
    /// Motion.
    private func toggle(_ model: CalendarRowModel) {
        let next: CalendarRowModel.ID? = openID == model.id ? nil : model.id
        if reduceMotion {
            openID = next
        } else {
            withAnimation(.smooth(duration: 0.2)) {
                openID = next
            }
        }
    }

    /// The quiet lines under the title, each a symbol in a column and its text, drawn only when
    /// its data exists, with the Preview badge at the block's top trailing corner. Every text
    /// from the calendar is plain text, never markup or a link, and the link line names the
    /// service, never the address.
    private func detailLines(_ model: CalendarRowModel) -> some View {
        let event = model.row.event
        return HStack(alignment: .top, spacing: HolzBarTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                if let place = place(of: event) {
                    detailLine("mappin.and.ellipse") {
                        Text(verbatim: place)
                            .lineLimit(1)
                    }
                }
                if let count = attendees(of: event) {
                    detailLine("person.2") {
                        Text("\(count) attendees")
                    }
                }
                if let link = model.link {
                    detailLine("link") {
                        Text(verbatim: serviceName(of: link))
                            .lineLimit(1)
                    }
                }
                if let excerpt = excerpt(of: event) {
                    detailLine("note.text") {
                        Text(verbatim: excerpt)
                            .lineLimit(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PreviewBadge()
        }
        .padding(.leading, Self.dotColumn + HolzBarTheme.Spacing.sm + Self.whenColumn + HolzBarTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One detail line: a 12 pt symbol in a 16 pt column, 8 pt, then the text.
    private func detailLine(_ symbol: String, @ViewBuilder text: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.Spacing.xs) {
            Image(systemName: symbol)
                .font(HolzBarTheme.Typography.callout)
                .frame(width: Self.symbolColumn)
                .accessibilityHidden(true)
            text()
                .font(HolzBarTheme.Typography.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        // One element per line, read in order; the symbol is decoration.
        .accessibilityElement(children: .combine)
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
