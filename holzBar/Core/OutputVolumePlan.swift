//
//  OutputVolumePlan.swift
//  holzBar
//

import Foundation

/// Which CoreAudio property serves the volume of a sound output, decided from plain flags.
///
/// An output does not always have a volume control, and the ones that have it offer it in
/// different ways: most offer a virtual main volume, some only the main channel's scalar volume,
/// some only a volume per channel. The app reads which properties the output has and which of
/// them can be set (``Capabilities``), asks for a plan here, and only then reads or writes a
/// value, so a value is never written to a property the system has not said it accepts.
nonisolated enum OutputVolumePlan: Equatable, Sendable {
    /// The virtual main volume, which the system keeps in step with the channels.
    case virtualMain
    /// The scalar volume of the main channel (element 0).
    case mainScalar
    /// The scalar volumes of single channels (elements 1 and above), sorted. The average is read
    /// and every channel is written.
    case channels([UInt32])
    /// The output has no volume the app can set.
    case unsupported

    /// What the app found out about an output.
    nonisolated struct Capabilities: Equatable, Sendable {
        /// The virtual main volume exists and can be set.
        var virtualMainSettable: Bool
        /// The main channel's scalar volume exists and can be set.
        var mainScalarSettable: Bool
        /// The channels (elements 1 and above) whose scalar volume exists and can be set. An
        /// element 0 in the list is ignored: that is the main channel.
        var settableChannels: [UInt32]
        /// The output's mute exists and can be set.
        var muteSettable: Bool
    }

    /// The plan for an output: the virtual main volume if it can be set, else the main
    /// channel's scalar volume, else the settable channels (sorted, without duplicates, and
    /// without element 0), else unsupported. Mute does not change the plan.
    static func resolve(_ capabilities: Capabilities) -> OutputVolumePlan {
        if capabilities.virtualMainSettable {
            return .virtualMain
        }
        if capabilities.mainScalarSettable {
            return .mainScalar
        }
        let channels = Set(capabilities.settableChannels.filter { $0 > 0 }).sorted()
        return channels.isEmpty ? .unsupported : .channels(channels)
    }

    /// The level of several channels: the average of the finite values, kept between 0 and 1 and
    /// rounded to four decimals, or `nil` when no value is finite.
    static func combined(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else {
            return nil
        }
        let average = finite.reduce(0, +) / Double(finite.count)
        // Four decimals, so that the sum of two floats does not leave a trailing digit.
        return (min(max(average, 0), 1) * 10_000).rounded() / 10_000
    }
}
