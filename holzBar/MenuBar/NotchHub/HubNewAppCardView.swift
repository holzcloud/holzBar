//
//  HubNewAppCardView.swift
//  holzBar
//

import AppKit
import SwiftUI

/// What the Notch hub reads of the question where a new menu bar app should go (Phase 97, D-06,
/// D-12, COMF-04). The question model registers with ``NotchHubModel/newAppQuestionSource`` when
/// it is created, so the hub controller never names it.
@MainActor
protocol HubNewAppQuestionSource: AnyObject {
    /// The apps that are asked about in the hub now: empty while the Shelf is used or the switch is
    /// off, so the hub's card never shows next to the Shelf's.
    var hubQuestions: [NewAppQuestion.App] { get }

    /// Whether the Always Hidden choice is offered.
    var offersAlwaysHidden: Bool { get }

    /// Answers the question of an app; a section answer is one Undo step with the toast at the
    /// menu bar.
    func answerFromHub(_ answer: NewAppQuestion.Answer, for bundleID: String)

    /// The icon of an app, or `nil`.
    func icon(for bundleID: String) -> NSImage?
}

/// The question where a new menu bar app should go, as the first row of the hub's Overview, in
/// the look of the expanded notification card (white 4.5 % fill, white 6 % border, radius 14).
///
/// One app gives the single card with the text chip Don't ask again; several give one combined
/// card with at most ``DesignTokens/Comfort/combinedQuestionMaxRows`` rows. The card is at most
/// ``DesignTokens/Indicator/cardMaximumHeight`` high: a card that is taller, because its chips
/// wrapped, scrolls inside itself and never grows the hub. It has no close button; Don't ask
/// again is the way to dismiss it.
struct HubNewAppCardView: View {
    let source: any HubNewAppQuestionSource

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private static let singleIconSize: CGFloat = 28
    private static let rowIconSize: CGFloat = 20

    var body: some View {
        let questions = source.hubQuestions
        let radius = CGFloat(DesignTokens.Hub.tileRadius)
        let fill = reduceTransparency ? DesignTokens.Hub.tileFillAlphaOpaque : DesignTokens.Hub.tileFillAlpha
        ViewThatFits(in: .vertical) {
            content(for: questions)
            ScrollView {
                content(for: questions)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: DesignTokens.Indicator.cardMaximumHeight, alignment: .topLeading)
        .background(.white.opacity(fill), in: HolzBarTheme.shape(radius))
        .overlay {
            HolzBarTheme.shape(radius)
                .stroke(.white.opacity(contrast == .increased ? 0.4 : 0.06), lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .clipShape(HolzBarTheme.shape(radius))
    }

    private func content(for questions: [NewAppQuestion.App]) -> some View {
        Group {
            if questions.count == 1, let app = questions.first {
                singleCard(for: app)
            } else {
                combinedCard(for: questions)
            }
        }
        .padding(HolzBarTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: One app

    private func singleCard(for app: NewAppQuestion.App) -> some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.sm) {
            icon(for: app, size: Self.singleIconSize)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                nameLine(of: app)
                Text("New in the menu bar")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .lineLimit(1)
                WrappingChipsLayout(spacing: HolzBarTheme.Spacing.xs, lineSpacing: HolzBarTheme.Spacing.xxs) {
                    ForEach(answers, id: \.self) { answer in
                        pill(answer, for: app)
                    }
                }
                .padding(.top, HolzBarTheme.Spacing.xxs)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Where should \(app.name) go?"))
    }

    // MARK: Several apps

    private func combinedCard(for questions: [NewAppQuestion.App]) -> some View {
        let shown = NewAppQuestion.shown(questions, limit: DesignTokens.Comfort.combinedQuestionMaxRows)
        return VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            Text("New in the menu bar")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Hub.neutral)
                .lineLimit(1)
            ForEach(shown.rows) { app in
                combinedRow(for: app)
            }
            if shown.more > 0 {
                Text("+\(shown.more) more")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .lineLimit(1)
            }
        }
    }

    /// One app of the combined card: on one line when it fits, else the name above the chips.
    private func combinedRow(for app: NewAppQuestion.App) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                icon(for: app, size: Self.rowIconSize)
                nameLine(of: app)
                Spacer(minLength: HolzBarTheme.Spacing.xs)
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    combinedPills(for: app)
                }
            }
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    icon(for: app, size: Self.rowIconSize)
                    nameLine(of: app)
                }
                WrappingChipsLayout(spacing: HolzBarTheme.Spacing.xs, lineSpacing: HolzBarTheme.Spacing.xxs) {
                    combinedPills(for: app)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Where should \(app.name) go?"))
    }

    @ViewBuilder
    private func combinedPills(for app: NewAppQuestion.App) -> some View {
        ForEach(answers.filter { $0 != .dontAskAgain }, id: \.self) { answer in
            pill(answer, for: app)
        }
        Button {
            source.answerFromHub(.dontAskAgain, for: app.bundleID)
        } label: {
            Image(systemName: "bell.slash")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Hub.neutral)
                .accessibilityHidden(true)
                .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Don't ask again"))
        .accessibilityLabel(Text("Don't ask again"))
    }

    // MARK: Parts

    /// The answers the question offers: the sections that are on, then Don't ask again.
    private var answers: [NewAppQuestion.Answer] {
        let offersAlwaysHidden = source.offersAlwaysHidden
        return NewAppQuestion.Answer.allCases.filter { offersAlwaysHidden || $0 != .alwaysHidden }
    }

    private func icon(for app: NewAppQuestion.App, size: CGFloat) -> some View {
        Group {
            if let image = source.icon(for: app.bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The app's name on one line, tail truncated with the full name as the tooltip, and the
    /// Preview badge after it.
    private func nameLine(of app: NewAppQuestion.App) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            Text(verbatim: app.name)
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Hub.pillText)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(app.name)
            PreviewBadge()
                .fixedSize()
        }
    }

    /// One answer as a pill in a 24 pt target: the sections on the pill fill, Don't ask again as
    /// quiet text without a fill.
    private func pill(_ answer: NewAppQuestion.Answer, for app: NewAppQuestion.App) -> some View {
        let isQuiet = answer == .dontAskAgain
        return Button {
            source.answerFromHub(answer, for: app.bundleID)
        } label: {
            title(of: answer)
                .font(HolzBarTheme.Hub.pillFont)
                .foregroundStyle(isQuiet ? HolzBarTheme.Hub.neutral : HolzBarTheme.Hub.pillText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, HolzBarTheme.Spacing.xs)
                .frame(minHeight: HolzBarTheme.Hub.pillHeight)
                .background(isQuiet ? Color.clear : HolzBarTheme.Hub.pillFill, in: Capsule())
                .overlay {
                    if contrast == .increased {
                        Capsule().stroke(HolzBarTheme.Hub.neutral)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(of answer: NewAppQuestion.Answer) -> Text {
        switch answer {
        case .visible:
            Text("Visible")
        case .hidden:
            Text("Hidden")
        case .alwaysHidden:
            Text("Always Hidden")
        case .dontAskAgain:
            Text("Don't ask again")
        }
    }
}
