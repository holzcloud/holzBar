//
//  BarClickTrace.swift
//  holzBar
//

import Foundation

/// The last few clicks in the menu bar, kept in memory as short lines of numbers and fixed
/// words, so a bug report can show where a click landed and who took it.
///
/// A line holds the pointer's horizontal position, the horizontal extent of the items around it
/// and fixed words; the only identifiers are those of Apple's own system items. It names no
/// third-party item, no application and no path, and it is never written to disk or to a log:
/// ``DiagnosticsReport`` prints it only when the user copies the diagnostics.
nonisolated struct BarClickTrace: Equatable, Sendable {
    /// How many clicks are kept; the oldest goes first.
    static let capacity = 6

    /// The lines, oldest first.
    private(set) var lines: [String] = []

    /// Adds a line and forgets the oldest ones beyond the capacity.
    mutating func record(_ line: String) {
        lines.append(line)
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    /// A click inside a display's menu bar, as the click bridge for system items saw it.
    ///
    /// - Parameters:
    ///   - seconds: The system uptime in whole seconds, to order the lines.
    ///   - x: The pointer's horizontal position.
    ///   - concealing: Whether items are concealed at that moment.
    ///   - item: The identifier of the system item at the pointer, if there is one.
    ///   - bridged: Whether the bridge took the click to replay it.
    ///   - systemItems: The horizontal extent of the system items on that display.
    ///   - ownItems: The horizontal extent of holzBar's own control items.
    ///   - overflow: The horizontal extent of the system overflow button, if macOS has one.
    static func barClick(
        seconds: Int,
        x: Int,
        concealing: Bool,
        item: String?,
        bridged: Bool,
        systemItems: [ClosedRange<Int>],
        ownItems: [ClosedRange<Int>],
        overflow: ClosedRange<Int>? = nil
    ) -> String {
        let prefix = "com.apple.menuextra."
        let itemWord = item.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : "other" } ?? "none"
        return "t \(seconds), bar click x \(x), concealing \(yesNo(concealing)), item \(itemWord), "
            + "bridged \(yesNo(bridged)), own \(extents(ownItems)), overflow \(extents(overflow.map { [$0] } ?? [])), "
            + "system \(extents(systemItems))"
    }

    /// A click that reached holzBar's own control item.
    ///
    /// - Parameters:
    ///   - seconds: The system uptime in whole seconds, to order the lines.
    ///   - section: The section the item belongs to, as a fixed word.
    ///   - wasHidden: Whether that section was hidden before the click.
    static func controlClick(seconds: Int, section: String, wasHidden: Bool) -> String {
        "t \(seconds), holzBar icon clicked, section \(section), was hidden \(yesNo(wasHidden))"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func extents(_ ranges: [ClosedRange<Int>]) -> String {
        ranges.isEmpty ? "none" : ranges.map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: " ")
    }
}
