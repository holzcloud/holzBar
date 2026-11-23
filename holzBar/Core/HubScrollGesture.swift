//
//  HubScrollGesture.swift
//  holzBar
//

import Foundation

/// Turns the scroll events over the closed notch into at most one action per swipe (D-14).
///
/// The Notch hub's gestures are a vertical swipe (down opens the hub, up closes it) and a sideways
/// one (toward the left skips to the next track, toward the right to the previous one). A scroll is
/// a stream of events, so this type decides when a stream has become one deliberate swipe:
///
/// - A trackpad (precise deltas) swipe acts once, when its accumulated delta on the dominant axis
///   reaches ``preciseThreshold``, and not again until the gesture ends. 20 points is a deliberate
///   short swipe; a one-finger nudge stays below it.
/// - A mouse wheel (line deltas) acts on one line, as Show on scroll acts on one notch
///   (jordanbaird/Ice#717), and then waits ``coolDown``, so a wheel that is spun does not act twice.
/// - Momentum samples (the glide after the fingers lift) never act.
/// - A device that reports precise deltas without phases acts at ``preciseThreshold`` like a
///   trackpad and then waits ``coolDown`` like a wheel; a pause longer than the cool-down starts a
///   new accumulation.
///
/// The direction is the user's: with natural scrolling on, the system flips the sign of every delta,
/// so the sign is corrected with the sample's ``Sample/isInverted`` and the same finger movement
/// acts the same either way. The type reads no clock; every sample brings its own moment.
nonisolated struct HubScrollGesture: Equatable, Sendable {
    /// Where a scroll event is in its gesture, as AppKit reports it.
    nonisolated enum Phase: Equatable, Sendable {
        /// The event has no phase (a wheel, or the field is not used).
        case none
        case began
        case changed
        case ended
        case cancelled
    }

    /// One scroll event, reduced to what the decision needs.
    nonisolated struct Sample: Equatable, Sendable {
        /// The horizontal delta as AppKit reports it (`scrollingDeltaX`).
        var dx: Double
        /// The vertical delta as AppKit reports it (`scrollingDeltaY`).
        var dy: Double
        /// Whether the deltas are points of a trackpad (`hasPreciseScrollingDeltas`); `false` for
        /// the lines of a mouse wheel.
        var isPrecise: Bool
        /// Whether the system flipped the sign of the deltas (`isDirectionInvertedFromDevice`,
        /// natural scrolling).
        var isInverted: Bool
        var phase: Phase
        /// The phase of the glide after the fingers lifted; `.none` for a sample of the fingers.
        var momentumPhase: Phase
        /// When the event happened.
        var at: Date
    }

    /// What a swipe asks for.
    nonisolated enum Action: Equatable, Sendable {
        /// A swipe down: open the hub.
        case open
        /// A swipe up: close the hub.
        case close
        /// A swipe toward the left: the next track.
        case next
        /// A swipe toward the right: the previous track.
        case previous
    }

    /// The accumulated delta, in points, at which a trackpad swipe acts.
    static let preciseThreshold = 20.0
    /// The delta, in lines, at which a wheel notch acts.
    static let lineThreshold = 1.0
    /// How long a wheel (or a device without phases) waits after an action.
    static let coolDown: TimeInterval = 0.4
    /// How long the flash of a skipped track stays over the closed notch (H9): shorter than an
    /// indicator's hold, because the swipe itself is the feedback and the flash only says it was
    /// understood. A constant of the gesture, not a visual token.
    static let flashSeconds: TimeInterval = 1

    /// The area a gesture counts in, in the display's coordinates (origin top-left, y downward): the
    /// closed shape's horizontal span (the notch, or the top-centre strip of a display without one)
    /// over the full height of the top row. Never the hover zone, which is wider or lower, so a swipe
    /// in an app below the menu bar can never act.
    static func area(of seed: NotchHubGeometry.Rect, menuBarHeight: Double) -> NotchHubGeometry.Rect {
        let bar = menuBarHeight.isFinite && menuBarHeight > 0 ? menuBarHeight : 0
        return NotchHubGeometry.Rect(x: seed.x, y: 0, width: seed.width, height: max(seed.height, bar))
    }

    private var sumX = 0.0
    private var sumY = 0.0
    /// Whether the gesture that is going on has acted.
    private var hasActed = false
    private var lastActionAt: Date?
    private var lastSampleAt: Date?

    init() {}

    /// Takes one scroll event and returns what it asks for, or `nil`. A swipe returns an action at
    /// most once.
    mutating func offer(_ sample: Sample) -> Action? {
        // The glide never acts and never changes what the fingers did.
        if sample.momentumPhase != .none {
            return nil
        }
        if !sample.isPrecise {
            return offerLine(sample)
        }
        switch sample.phase {
        case .none:
            return offerPhaseless(sample)
        case .ended, .cancelled:
            finishGesture()
            return nil
        case .began:
            finishGesture()
            return accumulate(sample)
        case .changed:
            return accumulate(sample)
        }
    }

    /// Forgets the gesture that is going on and the cool-down.
    mutating func reset() {
        finishGesture()
        lastActionAt = nil
        lastSampleAt = nil
    }

    // MARK: Devices

    /// A wheel notch is one gesture of its own.
    private mutating func offerLine(_ sample: Sample) -> Action? {
        if isCoolingDown(at: sample.at) {
            return nil
        }
        guard let action = action(dx: sample.dx, dy: sample.dy, threshold: Self.lineThreshold, sample: sample) else {
            return nil
        }
        lastActionAt = sample.at
        return action
    }

    /// A precise device that reports no phases: accumulate until the threshold, act, then wait.
    private mutating func offerPhaseless(_ sample: Sample) -> Action? {
        defer {
            lastSampleAt = sample.at
        }
        if isCoolingDown(at: sample.at) {
            sumX = 0
            sumY = 0
            return nil
        }
        if let last = lastSampleAt, sample.at.timeIntervalSince(last) > Self.coolDown {
            sumX = 0
            sumY = 0
        }
        sumX += sample.dx
        sumY += sample.dy
        guard let action = action(dx: sumX, dy: sumY, threshold: Self.preciseThreshold, sample: sample) else {
            return nil
        }
        sumX = 0
        sumY = 0
        lastActionAt = sample.at
        return action
    }

    /// A trackpad gesture: accumulate; act once.
    private mutating func accumulate(_ sample: Sample) -> Action? {
        guard !hasActed else {
            return nil
        }
        sumX += sample.dx
        sumY += sample.dy
        guard let action = action(dx: sumX, dy: sumY, threshold: Self.preciseThreshold, sample: sample) else {
            return nil
        }
        hasActed = true
        lastActionAt = sample.at
        return action
    }

    // MARK: Decision

    private mutating func finishGesture() {
        sumX = 0
        sumY = 0
        hasActed = false
    }

    private func isCoolingDown(at moment: Date) -> Bool {
        guard let last = lastActionAt else {
            return false
        }
        return moment.timeIntervalSince(last) < Self.coolDown
    }

    /// The action of a delta, once its dominant axis has reached the threshold. A tie is vertical.
    private func action(dx: Double, dy: Double, threshold: Double, sample: Sample) -> Action? {
        if abs(dy) >= abs(dx) {
            guard abs(dy) >= threshold else {
                return nil
            }
            // A finger moving down gives a negative delta, a positive one with natural scrolling.
            let isDown = sample.isInverted ? dy > 0 : dy < 0
            return isDown ? .open : .close
        }
        guard abs(dx) >= threshold else {
            return nil
        }
        // A finger moving to the left gives a positive delta, a negative one with natural scrolling.
        let isLeft = sample.isInverted ? dx < 0 : dx > 0
        return isLeft ? .next : .previous
    }
}
