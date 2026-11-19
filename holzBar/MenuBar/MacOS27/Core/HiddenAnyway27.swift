//
//  HiddenAnyway27.swift
//  holzBar
//

import CoreGraphics

/// Recognises visible applications whose items MenuBarAgent hides anyway on macOS 27.
///
/// MenuBarAgent keeps an item while an assertion is live only when the bundle identifier it
/// looked up for the item's process is on the allowlist. When that lookup gave nothing, no
/// entry matches and every live assertion hides the item, holzBar's included, though holzBar
/// keeps the application visible. Seen on macOS 27.2 with a device management agent started at
/// login: MenuBarAgent logged its item as `nil`, and allowlisting its bundle identifier, an
/// empty string or any of its names did not bring it back. The assertion has no other key that
/// could keep such an item (`MBAssessmentModeConfiguration` takes system item numbers and
/// bundle identifiers only), so holzBar can only notice it.
///
/// Accessibility keeps reporting the item's frame where it was last drawn, so it passes for
/// drawn. On a settled bar no two drawn items lie on top of each other: neighbours overlap by
/// 2 points (measured on macOS 27.0). An application's item that overlaps another drawn item
/// by more than that is not drawn. Beside holzBar's own items and the system items, whose
/// frames are live, the application is named; when two applications' items lie on top of each
/// other, both are named, since either may be the one not drawn. A frame left over empty bar
/// is not recognised.
nonisolated enum HiddenAnyway27 {
    /// An item a settled read takes for drawn.
    nonisolated struct DrawnItem: Equatable, Sendable {
        /// The bundle identifier of the application the item belongs to, or `nil` for an item
        /// whose frame is known to be live (holzBar's own items, the system items).
        let bundleID: String?
        let frame: CGRect
    }

    /// How far two drawn items may overlap: neighbours overlap by 2 points (measured on
    /// macOS 27.0), with the margin ``StuckOverflow27`` uses.
    static let tolerance: CGFloat = 6

    /// The applications whose items lie on top of another drawn item.
    ///
    /// - Parameter items: The items of one settled read taken for drawn: on the active display,
    ///   not folded away, of no concealed application. A frame no wider than ``tolerance``
    ///   (holzBar's collapsed items, an item squashed while its application launches) never lies
    ///   on top of another.
    static func suspects(among items: [DrawnItem]) -> Set<String> {
        var suspects = Set<String>()
        for (index, item) in items.enumerated() {
            for other in items[(index + 1)...] {
                // Two live frames, or two items of one application, tell nothing.
                guard item.bundleID != other.bundleID else {
                    continue
                }
                let overlap = item.frame.intersection(other.frame)
                guard !overlap.isNull, overlap.width > tolerance else {
                    continue
                }
                for bundleID in [item.bundleID, other.bundleID].compactMap(\.self) {
                    suspects.insert(bundleID)
                }
            }
        }
        return suspects
    }

    /// The applications to report: the suspects of this read that the read before named too.
    ///
    /// A frame can still be on its way for a moment after a change lands (an application shown
    /// for a click draws its item 0.4 to 0.6 s later, measured), so one read alone names none.
    static func confirmed(current: Set<String>, previous: Set<String>) -> Set<String> {
        current.intersection(previous)
    }
}
