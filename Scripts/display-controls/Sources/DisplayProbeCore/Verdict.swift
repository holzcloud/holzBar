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

    /// How the volume of an output is reached, as a word.
    public enum VolumePlan: String, Sendable {
        case virtualMain
        case mainScalar
        case channels
        case none

        /// The virtual main volume first, then the main element's scalar volume, then the
        /// scalar volumes of channels 1 and 2, else none.
        public static func choose(virtualMainSettable: Bool, mainScalarSettable: Bool, settableChannels: Int) -> VolumePlan {
            if virtualMainSettable { return .virtualMain }
            if mainScalarSettable { return .mainScalar }
            if settableChannels > 0 { return .channels }
            return .none
        }
    }

    /// How an output device is connected, as a word. A device name is never used.
    public enum Transport: String, Sendable {
        case builtIn = "built-in"
        case usb
        case bluetooth
        case hdmi
        case displayPort = "displayport"
        case other
    }

    /// Whether a volume listener reported the probe's own change.
    public enum ListenerState: String, Sendable {
        case fired
        case silent
        case notRun = "not run"
    }

    /// What the probe saw of the default output device's volume.
    public struct VolumeObservation: Sendable {
        public var plan: VolumePlan
        public var transport: Transport
        public var changeTested: Bool
        public var original: Double?
        public var target: Double?
        public var readBack: Double?
        public var restored: Double?
        public var muteSettable: Bool
        public var listener: ListenerState

        public init(
            plan: VolumePlan,
            transport: Transport = .other,
            changeTested: Bool = false,
            original: Double? = nil,
            target: Double? = nil,
            readBack: Double? = nil,
            restored: Double? = nil,
            muteSettable: Bool = false,
            listener: ListenerState = .notRun
        ) {
            self.plan = plan
            self.transport = transport
            self.changeTested = changeTested
            self.original = original
            self.target = target
            self.readBack = readBack
            self.restored = restored
            self.muteSettable = muteSettable
            self.listener = listener
        }
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

    /// VOLUME: the default output device.
    public static func volume(_ observation: VolumeObservation) -> (result: Result, reason: String) {
        if observation.plan == .none {
            // A monitor's own audio often has no volume control; that is not the criterion,
            // which names the built-in speakers and wired headphones.
            if observation.transport == .hdmi || observation.transport == .displayPort {
                return (.reducedGo, "no volume control on this transport")
            }
            return (.noGo, "no settable volume")
        }
        var reasons: [String] = []
        if !observation.changeTested {
            reasons.append("change not tested")
        } else {
            let target = observation.target ?? Self.target(from: observation.original ?? 0.5)
            if let readBack = observation.readBack, Tolerance.agrees(readBack, target) {
                if let original = observation.original, let restored = observation.restored,
                   Tolerance.agrees(restored, original) {
                    // The change read back and was restored.
                } else {
                    reasons.append("original not restored")
                }
            } else {
                reasons.append("change did not read back")
            }
        }
        if !observation.muteSettable {
            reasons.append("no settable mute")
        }
        switch observation.listener {
        case .fired: break
        case .silent: reasons.append("listener silent")
        case .notRun: reasons.append("listener not run")
        }
        return reasons.isEmpty ? (.go, "all criteria met") : (.reducedGo, reasons.joined(separator: ", "))
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
