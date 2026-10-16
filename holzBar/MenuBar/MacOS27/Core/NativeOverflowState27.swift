//
//  NativeOverflowState27.swift
//  holzBar
//

import CoreGraphics

/// What macOS 27's own overflow control ("«" / "»", which folds the items that do not fit
/// beside the notch) is doing on the active bar, as far as the reported frames tell.
///
/// `expanded` needs two agreeing facts: the control is there, no counted item lies on it, and
/// at least one counted item is drawn left of the notch. `unknown` means "do as before"
/// everywhere it is used. The only public description of the control is
/// badgeify.app/macos-27-golden-gate-menu-bar-changes; the measured rule that tells folded
/// items is ``OverflowDetection27``.
nonisolated enum NativeOverflowState27: String, Equatable, Sendable {
    /// The control is not there and nothing is folded.
    case none
    /// The control is there and the items that do not fit are stacked on it.
    case collapsed
    /// The control is there and the folded items are drawn left of the notch.
    case expanded
    /// The frames do not agree, or tell too little.
    case unknown

    /// Neighbours overlap by 2 points (measured on macOS 27.0); the margin ``StuckOverflow27`` uses.
    static let notchTolerance: CGFloat = 6

    /// Works out the state from the frames of one read of the bar.
    ///
    /// The expanded facts come from the public description and must be measured again with
    /// `Scripts/macos27/overflow-state-probe.swift`.
    ///
    /// - Parameters:
    ///   - chevronFrame: The frame of the overflow control, if there is one on the display.
    ///   - itemFrames: The frames to count. Choosing them is the caller's job: items on the
    ///     active display that are not concealed and not holzBar's own. Frames 4 points wide
    ///     or narrower (holzBar's collapsed items) are dropped here.
    ///   - notchSpan: The span the notch covers, see ``StuckOverflow27/notchSpan(displayBounds:leftAreaWidth:rightAreaWidth:)``,
    ///     or `nil` for a display without a notch.
    static func derive(chevronFrame: CGRect?, itemFrames: [CGRect], notchSpan: ClosedRange<CGFloat>?) -> NativeOverflowState27 {
        let frames = itemFrames.filter { $0.width > 4 }
        let isLeftOfNotch = notchSpan.map { span in
            frames.contains { $0.maxX - notchTolerance <= span.lowerBound }
        } ?? false
        guard let chevronFrame else {
            return isLeftOfNotch ? .unknown : .none
        }
        let isStacked = frames.contains { OverflowDetection27.isInOverflow(itemFrame: $0, chevronFrame: chevronFrame) }
        guard notchSpan != nil else {
            return isStacked ? .collapsed : .unknown
        }
        switch (isStacked, isLeftOfNotch) {
        case (true, false): return .collapsed
        case (false, true): return .expanded
        default: return .unknown
        }
    }
}

/// One read's state with the display it was read on and that display's notch span, so a
/// consumer can tell whether it applies to its own display.
nonisolated struct NativeOverflowReading27: Equatable, Sendable {
    let state: NativeOverflowState27
    let displayID: CGDirectDisplayID?
    let notchSpan: ClosedRange<CGFloat>?

    static let unknown = NativeOverflowReading27(state: .unknown, displayID: nil, notchSpan: nil)
}
