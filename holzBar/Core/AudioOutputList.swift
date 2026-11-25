//
//  AudioOutputList.swift
//  holzBar
//

import Foundation

/// How a sound output is connected, as far as the picker's symbol cares.
nonisolated enum AudioTransport: Equatable, Sendable {
    case builtIn
    case bluetooth
    case hdmi
    case displayPort
    case airPlay
    case usb
    /// A device that combines others. It is not listed.
    case aggregate
    /// A software device, such as a loopback. It is not listed.
    case virtual
    case other
}

/// One sound device as the system reports it, before the list is built.
nonisolated struct AudioOutputDevice: Equatable, Sendable {
    /// The device's UID, the key of the device: the object identifier changes when a device
    /// leaves and returns.
    let uid: String
    let name: String
    /// The number of output channels; a microphone has none.
    let outputChannels: Int
    let isHidden: Bool
    let transport: AudioTransport
}

/// One row of the output picker.
nonisolated struct AudioOutputRow: Equatable, Sendable, Identifiable {
    /// The device's UID.
    let id: String
    let name: String
    /// The SF Symbol of the device's transport.
    let symbol: String
    /// Whether the system's default output is this device.
    let isCurrent: Bool
}

/// The outputs the Display controls tab offers (D-16, PITFALLS 22).
///
/// Devices are keyed by UID, never by object identifier; the system decides which output is the
/// default, so the list only shows what the system reports and a switch is always read back
/// (``AudioOutputSwitch``). Aggregate, virtual and hidden devices and devices without output
/// channels are left out. Rows sort by name in the Finder's order with the UID as tie-break and
/// the current output is never moved to the top, so rows do not jump after a switch.
nonisolated enum AudioOutputList {
    /// The longest name kept, in characters; a longer one is cut.
    static let maximumNameLength = 80

    /// How long a switch waits for the system's default to match before it gives up quietly.
    static let switchTimeout: TimeInterval = 3

    /// The rows for the devices the system reports. `currentUID` is the default output's UID,
    /// or `nil` when it is unknown, which marks no row.
    static func rows(_ devices: [AudioOutputDevice], currentUID: String?) -> [AudioOutputRow] {
        var seen = Set<String>()
        let visible = devices.filter { device in
            device.outputChannels > 0
                && !device.isHidden
                && device.transport != .aggregate
                && device.transport != .virtual
                && seen.insert(device.uid).inserted
        }
        let sorted = visible.sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.uid < rhs.uid
            }
        }
        return sorted.map { device in
            AudioOutputRow(
                id: device.uid,
                name: String(device.name.prefix(maximumNameLength)),
                symbol: symbol(for: device.transport),
                isCurrent: device.uid == currentUID
            )
        }
    }

    /// The SF Symbol of a transport.
    static func symbol(for transport: AudioTransport) -> String {
        switch transport {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "headphones"
        case .hdmi, .displayPort: "display"
        case .airPlay: "airplayaudio"
        case .usb: "hifispeaker.fill"
        case .aggregate, .virtual, .other: "speaker.wave.2"
        }
    }

    /// Whether the name becomes a picker: there is something to choose from two outputs on.
    static func offersPicker(_ rows: [AudioOutputRow]) -> Bool {
        rows.count >= 2
    }
}

/// A switch of the default output that was asked for and not yet read back.
nonisolated struct AudioOutputSwitch: Equatable, Sendable {
    /// Where a switch stands.
    nonisolated enum State: Equatable, Sendable {
        /// The system's default is not the target yet.
        case pending
        /// The system's default is the target.
        case done
        /// ``AudioOutputList/switchTimeout`` passed and the default is still another device.
        case gaveUp
    }

    /// The UID of the device that was asked for.
    let targetUID: String
    let startedAt: Date

    /// The state at `now`, given the UID the system reports as the default. The read-back
    /// decides: a target that is reached counts as done even after the timeout.
    func state(currentUID: String?, now: Date) -> State {
        if currentUID == targetUID {
            return .done
        }
        return now.timeIntervalSince(startedAt) >= AudioOutputList.switchTimeout ? .gaveUp : .pending
    }
}
