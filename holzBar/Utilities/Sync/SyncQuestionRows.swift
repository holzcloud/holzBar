//
//  SyncQuestionRows.swift
//  holzBar
//

import Observation
import SwiftUI

// MARK: - Model

/// What the question sheet shows and what the user has chosen in it.
///
/// The rows are the engine's (``SyncQuestion``), in the order of the contract (``SyncRowOrdering``), with their texts. They
/// never change while the sheet is open: a question that arrives or changes meanwhile does not touch them. The only thing that
/// can happen to a row is that it is decided on another Mac (``refresh(current:)``), which dims it and leaves it out of the
/// answer. The model decides nothing: it only builds the answer the engine asked for (``request(for:)``).
@MainActor
@Observable
final class SyncQuestionModel {
    /// One value of a pop-up.
    struct Option: Identifiable {
        /// The index in ``SyncRow/folder`` that an answer writes.
        let id: Int
        let text: String
    }

    /// How a row is drawn.
    enum Layout {
        /// This Mac's value and the sync folder's, with the date of the folder's.
        case twoWay(thisMac: SyncValueDisplay, folder: SyncValueDisplay, changed: String?)
        /// Two hotkeys that would share a combination, as one sentence.
        case clash(String)
        /// Three or more values, or a conflict between other Macs: a pop-up with no default.
        case choice([Option])
    }

    /// One row of the sheet.
    struct Entry: Identifiable {
        let id: SyncUnitKey
        let label: String
        let layout: Layout
        /// The units whose dots the row showed: the row's own, and a clash partner's.
        let units: [SyncUnitKey]
        /// What VoiceOver reads for the whole row.
        let accessibilityLabel: String

        /// Whether the row needs a pick before an answer can be given.
        var needsChoice: Bool {
            if case .choice = layout {
                return true
            }
            return false
        }
    }

    /// The question as the engine gave it; the answer carries it back, so it supersedes only the dots the sheet showed.
    let question: SyncQuestion
    let entries: [Entry]

    /// The value picked in each pop-up: the index in ``SyncRow/folder``.
    var choices: [SyncUnitKey: Int] = [:]

    /// The rows that another Mac decided while the sheet was open.
    private(set) var decidedElsewhere: Set<SyncUnitKey> = []

    init(question: SyncQuestion, names: SyncRowNames) {
        self.question = question
        let ordered = SyncRowOrdering.sorted(question.rows) { SyncStatusText.rowLabel(for: $0, names: names) }
        entries = ordered.map { Self.entry(for: $0, names: names) }
    }

    // MARK: State

    /// The rows that still wait for the user, in order.
    var openEntries: [Entry] {
        entries.filter { !decidedElsewhere.contains($0.id) }
    }

    /// Whether every row was decided elsewhere: nothing is left to answer, and the last button reads Done.
    var isFinished: Bool {
        openEntries.isEmpty
    }

    /// The first pop-up that has no pick yet.
    var firstUndecidedChoice: SyncUnitKey? {
        openEntries.first { $0.needsChoice && choices[$0.id] == nil }?.id
    }

    /// Whether Use and Keep may be pressed: a row is left, and every pop-up has a pick.
    var canAnswer: Bool {
        !isFinished && firstUndecidedChoice == nil
    }

    // MARK: Answer

    /// The answer for `button`: the picks of the pop-ups that are still open, and the question as it was shown.
    func request(for button: SyncAnswerButton) -> SyncAnswerRequest {
        var picks: [SyncUnitKey: Int] = [:]
        for entry in openEntries where entry.needsChoice {
            picks[entry.id] = choices[entry.id]
        }
        return SyncAnswerRequest(button: button, choices: picks, question: question)
    }

    /// Looks at the question as it stands now, and marks the rows that are no longer open: the row is gone, or the dots the
    /// sheet showed for it were replaced. An entry that arrived after the sheet opened does not decide a row. A row once
    /// decided elsewhere stays so.
    func refresh(current: SyncQuestion?) {
        for entry in entries where !decidedElsewhere.contains(entry.id) {
            guard let current, current.rows.contains(where: { $0.unit == entry.id }) else {
                decidedElsewhere.insert(entry.id)
                continue
            }
            let isOpen = entry.units.allSatisfy { unit in
                Set(question.shown[unit] ?? []).isSubset(of: Set(current.shown[unit] ?? []))
            }
            if !isOpen {
                decidedElsewhere.insert(entry.id)
            }
        }
    }

    // MARK: Building

    private static func entry(for row: SyncRow, names: SyncRowNames) -> Entry {
        let label = SyncStatusText.rowLabel(for: row, names: names)
        switch row.style {
        case .twoWay:
            let thisMac = SyncStatusText.display(of: row.local?.value, in: row, names: names)
            let folder = SyncStatusText.display(of: row.folder.first?.value, in: row, names: names)
            let changed = row.folder.first.map { SyncStatusText.dateText(for: $0.at) }
            let spoken = String(localized: "\(label), this Mac: \(thisMac.text), sync folder: \(folder.text), \(changed ?? "")")
            return Entry(
                id: row.unit,
                label: label,
                layout: .twoWay(thisMac: thisMac, folder: folder, changed: changed),
                units: [row.unit],
                accessibilityLabel: spoken
            )
        case .clash(let partner):
            let sentence = SyncStatusText.clashText(for: row, partner: partner, names: names)
            return Entry(id: row.unit, label: label, layout: .clash(sentence), units: [row.unit, partner], accessibilityLabel: sentence)
        case .multi, .bystander:
            let options = row.folder.enumerated().map { index, value in
                let text = SyncStatusText.display(of: value.value, in: row, names: names).text
                if row.local?.value.digest == value.value.digest {
                    return Option(id: index, text: String(localized: "\(text) (this Mac)"))
                }
                return Option(id: index, text: "\(text) (\(SyncStatusText.dateText(for: value.at)))")
            }
            return Entry(id: row.unit, label: label, layout: .choice(options), units: [row.unit], accessibilityLabel: label)
        }
    }
}

// MARK: - Views

/// The rows of the sheet and the footer under them: 480 pt wide, and the list scrolls above ``listHeight``.
struct SyncQuestionRows: View {
    var model: SyncQuestionModel
    /// The height of the list: its own height, at most 240 pt.
    var listHeight: CGFloat

    /// The width of the accessory view.
    static let width: CGFloat = 480

    /// The height the list gets at most; a longer list scrolls.
    static let maximumListHeight: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                SyncQuestionGrid(model: model)
            }
            .frame(height: listHeight)
            .background(Color(nsColor: .controlBackgroundColor))
            Text("Using the sync folder's settings restarts holzBar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.width)
    }
}

/// The table: the setting, this Mac's value and the sync folder's, one row per setting, with a divider between rows.
struct SyncQuestionGrid: View {
    @Bindable var model: SyncQuestionModel
    @FocusState private var focused: SyncUnitKey?

    var body: some View {
        // Setting 160 pt at least and flexible, This Mac 120 pt, Sync folder 160 pt, with 16 pt between the columns.
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                Text("Setting")
                    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                Text("This Mac")
                    .frame(width: 120, alignment: .leading)
                    .padding(.vertical, 8)
                Text("Sync folder")
                    .frame(width: 160, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ForEach(model.entries) { entry in
                Divider()
                row(entry)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: SyncQuestionRows.width, alignment: .leading)
        .onAppear {
            focused = model.firstUndecidedChoice
        }
    }

    @ViewBuilder
    private func row(_ entry: SyncQuestionModel.Entry) -> some View {
        if model.decidedElsewhere.contains(entry.id) {
            GridRow {
                labelCell(entry, spoken: "\(entry.label), \(String(localized: "Already decided on another Mac"))")
                Text("Already decided on another Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .gridCellColumns(2)
                    .padding(.vertical, 8)
            }
            .opacity(0.5)
        } else {
            switch entry.layout {
            case .twoWay(let thisMac, let folder, let changed):
                GridRow {
                    labelCell(entry, spoken: entry.accessibilityLabel)
                    valueCell(thisMac, changed: nil, width: 120)
                    valueCell(folder, changed: changed, width: 160)
                }
            case .clash(let sentence):
                GridRow {
                    Text(sentence)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(sentence)
                        .padding(.vertical, 8)
                        .gridCellColumns(3)
                }
            case .choice(let options):
                GridRow {
                    labelCell(entry, spoken: entry.label)
                    Picker(selection: choice(of: entry)) {
                        Text("Choose a Value")
                            .tag(Int?.none)
                        Divider()
                        ForEach(options) { option in
                            Text(option.text)
                                .tag(Int?.some(option.id))
                        }
                    } label: {
                        Text("Value to use for \(entry.label)")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .focused($focused, equals: entry.id)
                    .accessibilityLabel("Value to use for \(entry.label)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .gridCellColumns(2)
                }
            }
        }
    }

    /// The pick of a pop-up: none until the user chooses.
    private func choice(of entry: SyncQuestionModel.Entry) -> Binding<Int?> {
        Binding {
            model.choices[entry.id]
        } set: { pick in
            model.choices[entry.id] = pick
        }
    }

    /// The setting's label: two lines at most, cut at the tail, with the whole text in the help tag. For a row of two values it
    /// carries what VoiceOver reads for the whole row, and the value cells stay silent.
    private func labelCell(_ entry: SyncQuestionModel.Entry, spoken: String) -> some View {
        Text(entry.label)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(entry.label)
            .accessibilityLabel(spoken)
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    /// A value, and under it the date of the change when there is one. Two lines at most, cut at the tail.
    private func valueCell(_ display: SyncValueDisplay, changed: String?, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let image = display.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                if !display.hidesText {
                    Text(display.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .help(display.text)
            if let changed {
                Text(changed)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .accessibilityHidden(true)
        .frame(width: width, alignment: .leading)
        .padding(.vertical, 8)
    }
}
