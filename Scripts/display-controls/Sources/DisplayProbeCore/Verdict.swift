//
//  Verdict.swift
//  display-controls
//

import Foundation

/// How closely two levels must agree for a read-back to count.
public enum Tolerance {
    public static func agrees(_ first: Double, _ second: Double, within: Double = 0.02) -> Bool {
        guard first.isFinite, second.isFinite else {
            return false
        }
        return abs(first - second) <= within
    }
}

/// The two results of the spike, as pure functions of what the probe observed. The criteria
/// are the table "Spike criteria" of the phase, fixed before any run.
public enum Verdict {
    public enum Result: String, Sendable {
        case go = "GO"
        case reducedGo = "REDUCED-GO"
        case noGo = "NO-GO"
    }

    /// What the probe saw of one display's brightness.
    public struct BrightnessObservation: Sendable {
        public var loaded: Bool
        public var symbolsResolved: Int
        public var canChange: Bool?
        public var value: Double?
        public var changeTested: Bool
        public var setSucceeded: Bool?
        public var readBack: Double?
        public var target: Double?
        public var original: Double?
        public var restored: Double?
        public var slowestCallMs: Double

        public init(
            loaded: Bool,
            symbolsResolved: Int,
            canChange: Bool? = nil,
            value: Double? = nil,
            changeTested: Bool = false,
            setSucceeded: Bool? = nil,
            readBack: Double? = nil,
            target: Double? = nil,
            original: Double? = nil,
            restored: Double? = nil,
            slowestCallMs: Double = 0
        ) {
            self.loaded = loaded
            self.symbolsResolved = symbolsResolved
            self.canChange = canChange
            self.value = value
            self.changeTested = changeTested
            self.setSucceeded = setSucceeded
            self.readBack = readBack
            self.target = target
            self.original = original
            self.restored = restored
            self.slowestCallMs = slowestCallMs
        }
    }

    /// What the probe saw of the default output device's volume. Declared here; the verdict
    /// function for it is `volume(_:)`.
    public struct VolumeObservation: Sendable {
        public init() {}
    }

    /// BRIGHTNESS: the built-in display, or an Apple display when the Mac has none.
    public static func brightness(_ observation: BrightnessObservation) -> (result: Result, reason: String) {
        if !observation.loaded {
            return (.noGo, "framework not loaded")
        }
        if observation.symbolsResolved < 3 {
            return (.noGo, "only \(observation.symbolsResolved) of 3 symbols resolved")
        }
        if observation.canChange != true {
            return (.noGo, observation.canChange == nil ? "CanChange not read" : "CanChange is false")
        }
        guard let value = observation.value, value.isFinite else {
            return (.noGo, "no value read")
        }
        if value < 0 || value > 1 {
            return (.noGo, "value outside 0 to 1")
        }
        if observation.slowestCallMs > 2000 {
            return (.noGo, "a call took longer than 2 seconds")
        }
        guard observation.changeTested else {
            return (.reducedGo, "read only")
        }
        guard observation.setSucceeded == true else {
            return (.reducedGo, "set failed")
        }
        let original = observation.original ?? value
        let target = observation.target ?? Self.target(from: original)
        guard let readBack = observation.readBack, Tolerance.agrees(readBack, target) else {
            return (.reducedGo, "set did not read back")
        }
        guard let restored = observation.restored, Tolerance.agrees(restored, original) else {
            return (.reducedGo, "original not restored")
        }
        return (.go, "all criteria met")
    }

    /// VOLUME: not implemented yet.
    public static func volume(_ observation: VolumeObservation) -> (result: Result, reason: String) {
        (.noGo, "not run")
    }

    /// The level a change test moves to: the original plus 0.05, or minus 0.05 when the
    /// original is above 0.95, and never below 0.05.
    public static func target(from original: Double) -> Double {
        guard original.isFinite else {
            return 0.5
        }
        let moved = original > 0.95 ? original - 0.05 : original + 0.05
        return min(1, max(0.05, moved))
    }

    /// The `external` value of the SUMMARY line: the numbers of the displays other than the
    /// built-in one that macOS can change, or nil when there are none.
    public static func externalList(_ displayIDs: [UInt32]) -> String? {
        displayIDs.isEmpty ? nil : displayIDs.map(String.init).joined(separator: ",")
    }

    /// The text of a result for the SUMMARY line: the word, and the reason unless it is GO.
    public static func text(_ judgement: (result: Result, reason: String)) -> String {
        judgement.result == .go ? judgement.result.rawValue : "\(judgement.result.rawValue) (\(judgement.reason))"
    }
}
