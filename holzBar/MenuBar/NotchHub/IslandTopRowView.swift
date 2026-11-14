//
//  IslandTopRowView.swift
//  holzBar
//

import SwiftUI

/// A live value drawn after an activity's symbol: a countdown, a percentage or a short word.
///
/// The system draws a countdown itself (`Text(timerInterval:)`), so holzBar runs no timer for it.
/// The open hub's right pill and, from the live state on, the widened notch use it, so both show
/// the same value the same way.
struct LiveValueText: View {
    let trailing: HubLiveState.Trailing
    let font: Font

    var body: some View {
        value
            .font(font)
            .foregroundStyle(HolzBarTheme.Hub.pillText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var value: some View {
        switch trailing {
        case .countdown(let end):
            // A range needs its start not after its end; the end may have passed since the
            // rule worked it out.
            let now = Date.now
            Text(timerInterval: now...max(now, end), countsDown: true, showsHours: false)
        case .percent(let percent):
            Text(Double(percent) / 100, format: .percent)
        case .word(let word):
            Text(verbatim: word)
        case .none:
            EmptyView()
        }
    }
}

/// The row of the open island beside the notch and the row below it: one status pill on each
/// side of the notch, and the settings gear at the right end of the context-line row (concept
/// section 10b, "Layout", decisions D-01, D-02 and D-07).
///
/// On the left is the Timers module's own pill. On the right is the top other live activity by the
/// board's fixed order (``HubStatusPills``), drawn as its symbol and short value
/// (``HubLiveState``), never as its title, its detail or a name: VoiceOver reads the title. A
/// `+n` badge counts the other live activities that do not show. A finished activity leaves the
/// pill without a timer: the view asks the system to draw it again at the moment each one leaves.
/// The pills keep ``NotchHubGeometry/clearance`` from the notch; the row beside the notch holds
/// only the pills, and the gear sits below the notch.
///
/// The view is as wide as the island's shape and as high as the shape down to the end of the
/// context-line row; every position is relative to the shape's top left corner.
struct IslandTopRowView: View {
    let model: NotchHubModel
    let layout: NotchHubGeometry.IslandLayout
    let host: any HubHost

    private var shapeWidth: CGFloat {
        CGFloat(layout.shape.width)
    }

    /// The inner edges of the black body, in the shape's own coordinates.
    private var innerInset: Double {
        DesignTokens.Island.openTopRadius + DesignTokens.Island.sidePadding
    }

    /// The room left and right of the notch, in the shape's own coordinates; a pill never goes
    /// closer than the clearance to the notch (half of it from the centre without a notch).
    private var leftRoom: (x: Double, width: Double) {
        let limit: Double
        if let notch = layout.notch {
            limit = notch.x - layout.shape.x - NotchHubGeometry.clearance
        } else {
            limit = layout.shape.width / 2 - NotchHubGeometry.clearance / 2
        }
        return (innerInset, max(limit - innerInset, 0))
    }

    private var rightRoom: (x: Double, width: Double) {
        let start: Double
        if let notch = layout.notch {
            start = notch.maxX - layout.shape.x + NotchHubGeometry.clearance
        } else {
            start = layout.shape.width / 2 + NotchHubGeometry.clearance / 2
        }
        let end = layout.shape.width - innerInset
        return (start, max(end - start, 0))
    }

    var body: some View {
        TimelineView(.explicit(refreshDates)) { context in
            let placement = HubStatusPills.place(
                pillModuleIDs: model.pills.map(\.id),
                activities: model.activities,
                now: context.date
            )
            ZStack(alignment: .topLeading) {
                leftPill(placement)
                rightPill(placement, now: context.date)
                gear
            }
        }
        .frame(
            width: shapeWidth,
            height: CGFloat(layout.contextRow.maxY - layout.shape.y),
            alignment: .topLeading
        )
    }

    /// Now, and each moment at which a finished activity of the right pill leaves.
    private var refreshDates: [Date] {
        let now = Date.now
        let expiries = model.activities
            .filter { $0.moduleID != HubStatusPills.leftModuleID }
            .compactMap { activity in activity.finishedAt?.addingTimeInterval(HubActivityBoard.finishedHold) }
            .filter { $0 > now }
            .sorted()
        return [now] + expiries
    }

    // MARK: The pills

    /// A pill's height and the centre of the top row: the pills sit in the row beside the notch.
    private var pillHeight: CGFloat {
        HolzBarTheme.Hub.tabSize.height
    }

    private var topRowCentreOffset: CGFloat {
        max((CGFloat(layout.topRowHeight) - pillHeight) / 2, 0)
    }

    /// The Timers module's own pill, leading at the island's inner left edge.
    @ViewBuilder
    private func leftPill(_ placement: HubStatusPills.Placement) -> some View {
        if let id = placement.left, let pill = model.pills.first(where: { $0.id == id })?.pill {
            let room = leftRoom
            HStack(spacing: HolzBarTheme.Spacing.xxs) {
                if let symbol = pill.symbol {
                    Image(systemName: symbol)
                }
                Text(verbatim: pill.text)
                    .monospacedDigit()
            }
            .font(HolzBarTheme.Hub.pillFont)
            .foregroundStyle(HolzBarTheme.Hub.pillText)
            .lineLimit(1)
            .padding(.horizontal, HolzBarTheme.Spacing.xs)
            .frame(height: pillHeight)
            .background(HolzBarTheme.Hub.pillFill, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pill.accessibilityLabel)
            .frame(width: CGFloat(room.width), alignment: .leading)
            .offset(x: CGFloat(room.x), y: topRowCentreOffset)
        }
    }

    /// The top other live activity: its symbol in its tint and its short value, then the `+n`
    /// badge; trailing at the island's inner right edge.
    @ViewBuilder
    private func rightPill(_ placement: HubStatusPills.Placement, now: Date) -> some View {
        if let activity = placement.right, let content = HubLiveState.make(board: placement.rightBoard, now: now) {
            let room = rightRoom
            HStack(spacing: HolzBarTheme.Hub.pillSpacing) {
                HStack(spacing: HolzBarTheme.Spacing.xxs) {
                    Image(systemName: content.symbol)
                        .foregroundStyle(content.tint.color)
                    LiveValueText(trailing: content.trailing, font: HolzBarTheme.Hub.pillFont)
                }
                .font(HolzBarTheme.Hub.pillFont)
                .padding(.horizontal, HolzBarTheme.Spacing.xs)
                .frame(height: pillHeight)
                .background(HolzBarTheme.Hub.pillFill, in: Capsule())
                // VoiceOver hears the title; the pill never draws it.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(activity.title)
                if content.extraCount > 0 {
                    badge(content.extraCount)
                }
            }
            .frame(width: CGFloat(room.width), alignment: .trailing)
            .offset(x: CGFloat(room.x), y: topRowCentreOffset)
        }
    }

    private func badge(_ count: Int) -> some View {
        Text(verbatim: "+\(count)")
            .font(HolzBarTheme.Hub.pillFont)
            .monospacedDigit()
            .foregroundStyle(HolzBarTheme.Hub.neutral)
            .padding(.horizontal, HolzBarTheme.Spacing.xs)
            .frame(height: pillHeight)
            .background(HolzBarTheme.Hub.pillFill, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("+\(count) more"))
    }

    // MARK: The gear

    /// The settings gear: at the right end of the context-line row, below the notch, so the row
    /// beside the notch keeps only the pills.
    private var gear: some View {
        let size = HolzBarTheme.Island.gearSize
        let rowCentre = layout.contextRow.y - layout.shape.y + layout.contextRow.height / 2
        return Button {
            host.openSettings(for: NotchHubController.moduleID)
        } label: {
            Image(systemName: "gearshape")
                .font(HolzBarTheme.Island.gearSymbolFont)
                .foregroundStyle(HolzBarTheme.Island.gearSymbol)
                .frame(width: size, height: size)
                .background(HolzBarTheme.Island.gearFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel(Text("Settings"))
        .offset(
            x: CGFloat(layout.shape.width - innerInset) - size,
            y: CGFloat(rowCentre) - size / 2
        )
    }
}
