//
//  SyncStatusText.swift
//  holzBar
//

import Foundation

/// The texts of the sync status: the lines in Settings → Advanced, the hint at the top of holzBar's menu and its
/// button. The engine says what to show (`SyncView`); this only turns it into words, in the order of the UI contract.
/// Nothing here decides, reads a file or polls.
enum SyncStatusText {
    /// How a line is drawn: secondary text, or orange for the two lines the contract names.
    enum Tone: Hashable {
        case secondary
        case warning
    }

    /// One line of the label stack of the sync row.
    struct Line: Identifiable, Hashable {
        let id: String
        let text: String
        let tone: Tone
    }

    // MARK: Hint

    /// The sentence of a hint: the state line in Settings and the header of the hint in holzBar's menu.
    static func menuText(for hint: SyncHint) -> String {
        switch hint {
        case .restart, .choose:
            String(localized: "Settings changed on another Mac")
        case .chooseAfterJoin:
            String(localized: "Choose which settings this Mac uses")
        }
    }

    /// The title of the one button of a hint, in Settings and in the menu.
    static func buttonTitle(for hint: SyncHint) -> String {
        switch hint {
        case .restart:
            String(localized: "Restart")
        case .choose, .chooseAfterJoin:
            String(localized: "Choose Settings…")
        }
    }

    // MARK: Status lines

    /// The text of a status line.
    static func text(for line: SyncStatusLine) -> String {
        switch line {
        case .joining(let waitingFiles):
            if waitingFiles > 0 {
                String(localized: "Reading the sync folder… (\(waitingFiles) files not downloaded yet)")
            } else {
                String(localized: "Reading the sync folder…")
            }
        case .bystander(let rows):
            String(localized: "Your other Macs differ on \(rows) settings")
        case .waitingFiles(let count):
            String(localized: "Waiting for \(count) files in the sync folder to download.")
        case .newerFormat:
            String(localized: "A Mac uses a newer holzBar. Update holzBar to sync with it.")
        case .olderHolzBar:
            String(localized: "A Mac with an older holzBar still uses this folder. Update holzBar there to sync with it.")
        case .oversizeIcon:
            String(localized: "Your custom holzBar icon is too large to sync.")
        case .unreadableFile:
            String(localized: "A sync file in the folder can't be read.")
        case .unusableValue:
            String(localized: "A setting from a newer holzBar can't be used here.")
        case .skippedFiles(let count):
            String(localized: "holzBar skipped \(count) sync files in the folder because there are too many.")
        case .tooLargeToPublish:
            String(localized: "This Mac's settings are too large to sync. The folder keeps the previous ones.")
        }
    }

    /// The tone of a status line: orange only for a sync file that can't be read; every other line is secondary text.
    static func tone(of line: SyncStatusLine) -> Tone {
        switch line {
        case .unreadableFile:
            .warning
        case .joining, .bystander, .waitingFiles, .newerFormat, .olderHolzBar, .oversizeIcon, .unusableValue, .skippedFiles, .tooLargeToPublish:
            .secondary
        }
    }

    /// The place of a line in the label stack: the join, then the hint, then the bystander line, then the notes.
    private static func rank(of line: SyncStatusLine) -> Int {
        switch line {
        case .joining: 0
        case .bystander: 2
        case .waitingFiles: 3
        case .newerFormat: 4
        case .olderHolzBar: 5
        case .oversizeIcon: 6
        case .unreadableFile: 7
        case .unusableValue: 8
        case .tooLargeToPublish: 9
        case .skippedFiles: 10
        }
    }

    /// The place of the hint's sentence: after the join line and before the bystander line.
    private static let hintRank = 1

    /// The folder line: "Through <folder>", or the orange line that the folder can't be found.
    static func folderLine(name: String?) -> Line {
        if let name {
            Line(id: "folder", text: String(localized: "Through \(name)"), tone: .secondary)
        } else {
            Line(id: "folder", text: String(localized: "The sync folder cannot be found. Choose it again."), tone: .warning)
        }
    }

    /// Every line of the sync row under its title, after the folder line, in the order of the contract: the state line
    /// (the join, the hint, the bystander line), then the notes. Each is one sentence.
    static func lines(of view: SyncView) -> [Line] {
        var ranked: [(rank: Int, line: Line)] = view.lines.map { line in
            (rank(of: line), Line(id: "\(line)", text: text(for: line), tone: tone(of: line)))
        }
        if let hint = view.hint {
            ranked.append((hintRank, Line(id: "hint", text: menuText(for: hint), tone: .secondary)))
        }
        return ranked.sorted { $0.rank < $1.rank }.map(\.line)
    }

    /// Whether a join reads the folder or waits for the answer: Change… and Turn Off give way to Cancel.
    static func isJoining(_ view: SyncView) -> Bool {
        if view.hint == .chooseAfterJoin {
            return true
        }
        return view.lines.contains { line in
            if case .joining = line {
                return true
            }
            return false
        }
    }

    /// Whether a join reads the folder, and no question waits yet: Cancel is the only button.
    static func isReading(_ view: SyncView) -> Bool {
        isJoining(view) && view.hint != .chooseAfterJoin
    }
}
