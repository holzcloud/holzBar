//
//  HolzBarShelfNotice.swift
//  holzBar
//

import SwiftUI

/// The notice row under the tiles of the holzBar Shelf (Phase 97, D-08, D-24, concept M2): while
/// the fit model says the bar is full or macOS folded items away, it says so in the Layout
/// pane's words and offers the same one-click move of apps to Hidden, with the undo toast at
/// the menu bar.
///
/// The row is the Shelf's own look: the Shelf's text colour, the Shelf's chip, no accent and no
/// glass. It draws nothing while the apps fit and no app waits for an answer. The row keeps the
/// model running while the Shelf is open and stops it when the Shelf goes, so nothing evaluates
/// while the Shelf is closed.
///
/// The row also carries the question where a new menu bar app should go (D-12, COMF-04): the
/// banner shows first and the question after it is gone, never both. The question has no close
/// button; Don't ask again is the way to dismiss it.
@available(macOS 27.0, *)
struct HolzBarShelfNotice: View {
    /// The identifier of the chip that moves the apps, for the Shelf's keyboard highlight.
    static let moveChipID = "notice.move"

    let appState: AppState
    /// The tile or chip the keyboard highlights, while the Shelf takes keys.
    var highlightedID: String?

    private var makeRoom: MakeRoom27 {
        appState.makeRoom27
    }

    /// The first part of the identifier of a question's chip: `notice.q.<bundle identifier>.<answer>`.
    private static let questionChipPrefix = "notice.q."

    /// Whether the banner form is drawn now; it comes before the question.
    private static func isBannerShown(appState: AppState) -> Bool {
        appState.makeRoom27.shelfBanner?.verdict.isOverflowing == true
    }

    /// The apps that are asked about now, while the switch is on. Reading never creates the
    /// question model: an event does, so with the switch off there is none.
    private static func questionsAsked(appState: AppState) -> [NewAppQuestion.App] {
        guard appState.settings.advanced.asksWhereNewAppGoes else {
            return []
        }
        return appState.existingNewAppQuestions27?.asked ?? []
    }

    /// The answers the question offers: the sections that are on, then Don't ask again.
    private static func answersOffered(appState: AppState) -> [NewAppQuestion.Answer] {
        let offersAlwaysHidden = appState.newAppQuestions27.offersAlwaysHidden
        return NewAppQuestion.Answer.allCases.filter { offersAlwaysHidden || $0 != .alwaysHidden }
    }

    /// Whether the row is drawn now.
    static func isShown(appState: AppState) -> Bool {
        isBannerShown(appState: appState) || !questionsAsked(appState: appState).isEmpty
    }

    /// The chips the keyboard can reach, in order: the move chip while an app may move, and after
    /// the banner the chips of the question.
    static func chipIDs(appState: AppState) -> [String] {
        let makeRoom = appState.makeRoom27
        if isBannerShown(appState: appState) {
            guard
                let banner = makeRoom.shelfBanner,
                !banner.candidates.isEmpty,
                !makeRoom.isRunningPass
            else {
                return []
            }
            return [moveChipID]
        }
        let answers = answersOffered(appState: appState)
        let asked = questionsAsked(appState: appState)
        let rows = NewAppQuestion.shown(asked, limit: DesignTokens.Comfort.combinedQuestionMaxRows).rows
        return rows.flatMap { app in
            answers.map { chipID(bundleID: app.bundleID, answer: $0) }
        }
    }

    /// What a click or the keyboard on a chip does: the same pass as the Layout banner's button,
    /// or an answer to the question.
    static func activate(chipID: String, appState: AppState) {
        if chipID == moveChipID {
            appState.makeRoom27.moveCandidates(place: .menuBar)
            return
        }
        guard let (bundleID, answer) = parse(chipID: chipID) else {
            return
        }
        appState.existingNewAppQuestions27?.answer(answer, for: bundleID, place: .menuBar)
    }

    private static func chipID(bundleID: String, answer: NewAppQuestion.Answer) -> String {
        "\(questionChipPrefix)\(bundleID).\(answer.rawValue)"
    }

    /// The bundle identifier and the answer of a question chip's identifier. The identifier of an
    /// app contains dots, the answer is what follows the last one.
    private static func parse(chipID: String) -> (bundleID: String, answer: NewAppQuestion.Answer)? {
        guard chipID.hasPrefix(questionChipPrefix) else {
            return nil
        }
        let rest = chipID.dropFirst(questionChipPrefix.count)
        guard
            let dot = rest.lastIndex(of: "."),
            let answer = NewAppQuestion.Answer(rawValue: String(rest[rest.index(after: dot)...]))
        else {
            return nil
        }
        return (String(rest[..<dot]), answer)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = makeRoom.shelfBanner, banner.verdict.isOverflowing {
                row(for: banner)
            } else {
                let asked = Self.questionsAsked(appState: appState)
                if asked.count == 1, let app = asked.first {
                    questionRow(for: app)
                } else if asked.count > 1 {
                    combinedRow(for: asked)
                }
            }
        }
        // The row is always in the tree, so it learns when the Shelf opens and goes even while
        // the apps fit. With "When the menu bar is full" Off the model does not run for the Shelf
        // at all, and the setting applies at once.
        .background {
            Color.clear
                .onAppear {
                    if makeRoom.offersInShelf {
                        makeRoom.surfaceDidOpen(.shelf)
                    }
                }
                .onDisappear {
                    makeRoom.surfaceDidClose(.shelf)
                }
                .onChange(of: makeRoom.offersInShelf) { _, offers in
                    if offers {
                        makeRoom.surfaceDidOpen(.shelf)
                    } else {
                        makeRoom.surfaceDidClose(.shelf)
                    }
                }
        }
    }

    private func row(for banner: MakeRoom27.Banner) -> some View {
        let sentence = makeRoom.sentence(for: banner)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(HolzBarTheme.Palette.stroke)
                .frame(height: HolzBarTheme.Spacing.hairline)
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(HolzBarTheme.Typography.caption)
                    .accessibilityHidden(true)
                Text(sentence)
                    .font(HolzBarTheme.Typography.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: HolzBarTheme.Spacing.xs)
                PreviewBadge()
                    .fixedSize()
                chip(for: banner)
            }
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
            .padding(.vertical, HolzBarTheme.Spacing.xs)
            .frame(
                minWidth: DesignTokens.Comfort.shelfNoticeMinWidth,
                maxWidth: DesignTokens.Comfort.shelfNoticeMaxWidth
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One container after the tiles; the chip inside it is a named button.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(sentence))
    }

    // MARK: - The question

    /// The notice row's frame: the hairline above, the row's padding and its width.
    private func container(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(HolzBarTheme.Palette.stroke)
                .frame(height: HolzBarTheme.Spacing.hairline)
            content()
                .padding(.horizontal, HolzBarTheme.Spacing.sm)
                .padding(.vertical, HolzBarTheme.Spacing.xs)
                .frame(
                    minWidth: DesignTokens.Comfort.shelfNoticeMinWidth,
                    maxWidth: DesignTokens.Comfort.shelfNoticeMaxWidth,
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The question for one app: its icon, its name with the Preview badge, the caption, and the
    /// chips below. The block is one container whose chips are named buttons.
    private func questionRow(for app: NewAppQuestion.App) -> some View {
        container {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    icon(for: app, size: Self.iconSize)
                    VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                        nameLine(of: app)
                        Text("New in the menu bar")
                            .font(HolzBarTheme.Typography.caption)
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                WrappingChipsLayout(spacing: HolzBarTheme.Spacing.xs, lineSpacing: HolzBarTheme.Spacing.xxs) {
                    ForEach(Self.answersOffered(appState: appState), id: \.self) { answer in
                        chip(answer, for: app)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Where should \(app.name) go?"))
    }

    /// Several new apps as one card: the header, one row for each of the first apps and the quiet
    /// count of the others, which are asked next.
    private func combinedRow(for asked: [NewAppQuestion.App]) -> some View {
        let shown = NewAppQuestion.shown(asked, limit: DesignTokens.Comfort.combinedQuestionMaxRows)
        return container {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text("New in the menu bar")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineLimit(1)
                ForEach(shown.rows) { app in
                    combinedAppRow(for: app)
                }
                if shown.more > 0 {
                    Text("+\(shown.more) more")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    /// One app of the combined card: on one line when it fits, else the name above the chips. The
    /// three section chips come first, then the icon-only Don't ask again button.
    private func combinedAppRow(for app: NewAppQuestion.App) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                icon(for: app, size: Self.iconSize)
                nameLine(of: app)
                Spacer(minLength: HolzBarTheme.Spacing.xs)
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    combinedChips(for: app)
                }
            }
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    icon(for: app, size: Self.iconSize)
                    nameLine(of: app)
                }
                WrappingChipsLayout(spacing: HolzBarTheme.Spacing.xs, lineSpacing: HolzBarTheme.Spacing.xxs) {
                    combinedChips(for: app)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Where should \(app.name) go?"))
    }

    @ViewBuilder
    private func combinedChips(for app: NewAppQuestion.App) -> some View {
        ForEach(Self.answersOffered(appState: appState).filter { $0 != .dontAskAgain }, id: \.self) { answer in
            chip(answer, for: app)
        }
        dontAskAgainButton(for: app)
    }

    /// Don't ask again as an icon-only button in a 24 pt target.
    private func dontAskAgainButton(for app: NewAppQuestion.App) -> some View {
        let id = Self.chipID(bundleID: app.bundleID, answer: .dontAskAgain)
        let isHighlighted = highlightedID == id
        let appState = appState
        return Image(systemName: "bell.slash")
            .font(HolzBarTheme.Typography.caption)
            .accessibilityHidden(true)
            .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
            .contentShape(Rectangle())
            .overlay {
                HolzBarShelfClickView(
                    toolTip: Self.title(of: .dontAskAgain),
                    leftClickAction: {
                        Self.activate(chipID: id, appState: appState)
                    },
                    rightClickAction: nil,
                    drag: nil
                )
            }
            .keyboardHighlight(isHighlighted)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            .accessibilityLabel(Text("Don't ask again"))
            .accessibilityAction(.default) {
                Self.activate(chipID: id, appState: appState)
            }
    }

    /// The icon size of a question's row.
    private static let iconSize: CGFloat = 20

    private func icon(for app: NewAppQuestion.App, size: CGFloat) -> some View {
        Group {
            if let image = appState.existingNewAppQuestions27?.icon(for: app.bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
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
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(app.name)
            PreviewBadge()
                .fixedSize()
        }
    }

    /// The text of an answer's chip, which is also its tooltip.
    private static func title(of answer: NewAppQuestion.Answer) -> String {
        switch answer {
        case .visible:
            String(localized: "Visible")
        case .hidden:
            String(localized: "Hidden")
        case .alwaysHidden:
            String(localized: "Always Hidden")
        case .dontAskAgain:
            String(localized: "Don't ask again")
        }
    }

    /// One answer's chip in the Shelf's chip look.
    private func chip(_ answer: NewAppQuestion.Answer, for app: NewAppQuestion.App) -> some View {
        let id = Self.chipID(bundleID: app.bundleID, answer: answer)
        let isHighlighted = highlightedID == id
        let title = Self.title(of: answer)
        let appState = appState
        return Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.18)))
            .padding(.horizontal, 3)
            .frame(minHeight: HolzBarTheme.minimumTargetSize)
            .contentShape(Rectangle())
            .overlay {
                HolzBarShelfClickView(
                    toolTip: title,
                    leftClickAction: {
                        Self.activate(chipID: id, appState: appState)
                    },
                    rightClickAction: nil,
                    drag: nil
                )
            }
            .keyboardHighlight(isHighlighted)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityAction(.default) {
                Self.activate(chipID: id, appState: appState)
            }
    }

    /// The move chip, the busy state while a pass runs, or nothing when no app may move.
    @ViewBuilder
    private func chip(for banner: MakeRoom27.Banner) -> some View {
        if makeRoom.isRunningPass {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Applying…")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        } else if !banner.candidates.isEmpty {
            let isHighlighted = highlightedID == Self.moveChipID
            let appState = appState
            // The Shelf's chip, copied from the fold tile so the two look like siblings.
            Text("Move \(banner.candidates.count) to Hidden")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.18)))
                .padding(.horizontal, 3)
                .frame(minHeight: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
                .overlay {
                    HolzBarShelfClickView(
                        toolTip: makeRoom.info(for: banner),
                        leftClickAction: {
                            Self.activate(chipID: Self.moveChipID, appState: appState)
                        },
                        rightClickAction: nil,
                        drag: nil
                    )
                }
                .keyboardHighlight(isHighlighted)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(isHighlighted ? .isSelected : [])
                .accessibilityLabel(Text("Move \(banner.candidates.count) to Hidden"))
                .accessibilityAction(.default) {
                    Self.activate(chipID: Self.moveChipID, appState: appState)
                }
        }
    }
}
