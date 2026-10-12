//
//  Report.swift
//  holzBar
//

import CoreGraphics

/// Turns the bundle identifiers of non-Apple apps other than holzBar into `app1`, `app2`, ...
/// numbered by first appearance, so a report can be shared without naming the apps in the bar.
public struct Redactor: Sendable {
    private let enabled: Bool
    private var aliases = [String: String]()

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    /// The owner as it is written: unchanged for Apple and holzBar, `app<n>` otherwise.
    public mutating func shownOwner(_ owner: String) -> String {
        guard enabled, !owner.hasPrefix("com.apple."), owner != "com.holzcloud.holzBar" else {
            return owner
        }
        if let alias = aliases[owner] {
            return alias
        }
        let alias = "app\(aliases.count + 1)"
        aliases[owner] = alias
        return alias
    }

    /// An item id (`<owner>#<n>`) as it is written; the `#n` stays.
    public mutating func shownID(_ id: String) -> String {
        guard enabled else {
            return id
        }
        guard let hash = id.lastIndex(of: "#") else {
            return shownOwner(id)
        }
        return shownOwner(String(id[..<hash])) + id[hash...]
    }
}

/// The counts and the medians of one run, written as the SUMMARY line.
public struct RunSummary: Sendable {
    private var drags = 0
    private var moved = 0
    private var reorder = 0
    private var section = 0
    private var bouncy = 0
    private var vanished = 0
    private var notPersisted = 0
    private var refused = 0
    private var landedChecked = 0
    private var landedYes = 0
    private var settleTimes = [Int]()
    private var clickDelays = [Int]()
    private var tracks = 0
    private var maxShift: CGFloat?

    /// The longest callback of the tap in microseconds, set by the session at the end of the run.
    public var tapMaxUs: Int?

    public init() {}

    /// Counts one drag. `landed` is whether the intent path saw the move (`nil` when nothing was
    /// checked) and `refused` whether the move was refused.
    public mutating func add(_ result: SettleResult, landed: Bool?, refused: Bool) {
        drags += 1
        moved += result.moved ? 1 : 0
        reorder += result.scope == .reorder ? 1 : 0
        section += result.scope == .section ? 1 : 0
        bouncy += result.bounces > 0 ? 1 : 0
        vanished += result.vanished ? 1 : 0
        notPersisted += result.persisted == false ? 1 : 0
        self.refused += refused ? 1 : 0
        if let settleMs = result.settleMs {
            settleTimes.append(settleMs)
        }
        if let landed {
            landedChecked += 1
            landedYes += landed ? 1 : 0
        }
    }

    /// Counts one click that was held back and replayed.
    public mutating func addClick(delayMs: Int) {
        clickDelays.append(delayMs)
    }

    /// Counts one tracking check of the overlay: how many handles had to shift and by how much.
    public mutating func addTrack(shifted: Int, maxShift: CGFloat) {
        tracks += 1
        self.maxShift = Swift.max(self.maxShift ?? 0, maxShift)
    }

    /// The element at index `(count - 1) / 2` of the sorted values.
    private func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        return values.sorted()[(values.count - 1) / 2]
    }

    /// The SUMMARY line, with the keys of the output contract in order.
    public func line(mechanism: String, generation: Generation) -> ReportLine {
        var line = ReportLine("SUMMARY")
        line.add("mech", mechanism)
        line.add("generation", generation.rawValue)
        line.add("drags", drags)
        line.add("moved", moved)
        line.add("reorder", reorder)
        line.add("section", section)
        line.add("medianSettleMs", median(settleTimes))
        line.add("maxSettleMs", settleTimes.max())
        line.add("bouncy", bouncy)
        line.add("vanished", vanished)
        line.add("notPersisted", notPersisted)
        line.add("landed", landedChecked == 0 ? "-" : "\(landedYes)/\(landedChecked)")
        line.add("refused", refused)
        line.add("clicks", clickDelays.count)
        line.add("medianClickDelayMs", median(clickDelays))
        line.add("tapMaxUs", tapMaxUs)
        line.add("tracks", tracks)
        line.add("maxShiftPt", tracks == 0 ? nil : maxShift)
        return line
    }
}

/// The questions the probe asks at the end of a run, on a terminal only.
public enum Question: String, CaseIterable, Sendable {
    case flicker
    case natural
    case clicksFine
    case overlayAligned
    case holzBarFine

    public var text: String {
        switch self {
        case .flicker: "Did the menu bar flicker or jump during a drag?"
        case .natural: "Did dragging feel natural, like moving the item itself?"
        case .clicksFine: "Did every plain click still open its menu, and pressing into a menu still work?"
        case .overlayAligned: "Did the handles stay on the icons after each change you made?"
        case .holzBarFine: "Did holzBar keep working normally (its icon, hiding, the Shelf)?"
        }
    }

    /// The questions that make sense for a mechanism.
    public static func questions(for mechanism: String) -> [Question] {
        switch mechanism {
        case "a1": [.flicker, .natural, .holzBarFine]
        case "a2": [.flicker, .natural, .clicksFine, .holzBarFine]
        case "b": [.flicker, .natural, .overlayAligned, .holzBarFine]
        default: []
        }
    }

    /// The ANSWER line: `n/a` for a question not asked, `y` or `n` for an answer of yes or no,
    /// `skip` for anything else, also for a question asked and not answered.
    public static func answerLine(asked: [Question], answers: [Question: String]) -> ReportLine {
        var line = ReportLine("ANSWER")
        for question in allCases {
            guard asked.contains(question) else {
                line.add(question.rawValue, "n/a")
                continue
            }
            switch answers[question]?.lowercased() {
            case "y", "yes": line.add(question.rawValue, "y")
            case "n", "no": line.add(question.rawValue, "n")
            default: line.add(question.rawValue, "skip")
            }
        }
        return line
    }
}
