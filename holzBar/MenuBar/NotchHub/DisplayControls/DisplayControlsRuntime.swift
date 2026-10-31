//
//  DisplayControlsRuntime.swift
//  holzBar
//

import AppKit
import CoreAudio
import Foundation
import Observation
import SwiftUI

/// The running part of the Display controls module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. It reads the volume
/// of the default sound output when the hub opens and when its tab appears, and sets it; the
/// level it shows is always the one read back from the system, never the one requested. While
/// the hub is open, CoreAudio listeners tell it of a change made elsewhere (a volume key, the
/// menu bar, another device becoming the default); they are removed the moment the hub closes.
/// Nothing is polled. The output's name is read for the open tab only; it is kept in memory and
/// never logged, and neither the tile nor the pill carries it.
@MainActor
@Observable
final class DisplayControlsRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "display-controls"

    let moduleID = DisplayControlsRuntime.identifier
    let tint = HubTint.amber
    let offersTab = true

    /// The default output's level from 0 to 1, or `nil` when it has none or it cannot be read.
    private(set) var volume: Double?

    /// How the default output's volume is reached.
    private(set) var plan = OutputVolumePlan.unsupported

    /// Whether the output is muted. `false` when it has no mute.
    private(set) var isMuted = false

    /// Whether the output has a mute that can be set.
    private(set) var canMute = false

    /// The output's name, for the open tab only.
    private(set) var outputName: String?

    /// The built-in display's brightness from 0 to 1, or `nil` when it cannot be read.
    private(set) var brightness: Double?

    /// Whether the brightness part may run. It starts switched off and is replaced the first
    /// time the brightness is needed.
    private(set) var gate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// The built-in display the brightness belongs to.
    @ObservationIgnored private var brightnessDisplay: CGDirectDisplayID?

    /// The device the volume was read from.
    @ObservationIgnored private var device: AudioObjectID?

    /// The CoreAudio listeners, added while the hub is open.
    @ObservationIgnored private let listener = OutputVolume.Listener()

    /// Creates the runtime. It has nothing to start: the state is read when the hub opens.
    init(appState _: AppState) {}

    /// Reads the default output's plan, level, mute and name again, and the brightness.
    func refresh() {
        refreshBrightness()
        guard let output = OutputVolume.current() else {
            clear()
            return
        }
        device = output.device
        plan = output.plan
        volume = OutputVolume.volume(of: output.device, plan: output.plan)
        canMute = output.capabilities.muteSettable
        isMuted = canMute ? OutputVolume.isMuted(output.device) ?? false : false
        outputName = OutputVolume.name(of: output.device)
    }

    /// Sets the level. The level shown afterwards is the one read back, not the argument.
    func setVolume(_ value: Double) {
        guard let device, plan != .unsupported else {
            return
        }
        OutputVolume.setVolume(value, of: device, plan: plan)
        volume = OutputVolume.volume(of: device, plan: plan)
    }

    /// Reads the built-in display's brightness. The brightness wrapper is loaded here, the first
    /// time and never before; a failed read counts against the gate.
    func refreshBrightness() {
        guard PrivateFeatureGate.shouldLoad(isEnabled: true) else {
            return
        }
        // Loading happens once; asking again returns the same result and changes nothing.
        gate.setEnabled(true, load: DisplayServicesBrightness.load())
        guard gate.isAvailable else {
            brightness = nil
            return
        }
        guard let display = NSScreen.screens.map(\.displayID).first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
            brightness = nil
            return
        }
        brightnessDisplay = display
        if let value = DisplayServicesBrightness.read(display) {
            brightness = value
            gate.recordSuccess()
        } else {
            brightness = nil
            gate.recordFailure()
        }
    }

    /// Sets the brightness of the built-in display. The level shown afterwards is the one read
    /// back, not the argument.
    func setBrightness(_ value: Double) {
        guard gate.isAvailable, let display = brightnessDisplay else {
            return
        }
        guard DisplayServicesBrightness.write(value, to: display),
              let readBack = DisplayServicesBrightness.read(display)
        else {
            gate.recordFailure()
            return
        }
        brightness = readBack
        gate.recordSuccess()
    }

    /// Moves the brightness by steps of 5 percent, for the keyboard and VoiceOver.
    func adjustBrightness(by steps: Int) {
        guard let brightness else {
            return
        }
        setBrightness(DisplayControlsLevel.stepped(brightness, by: steps))
    }

    /// Moves the level by steps of 5 percent, for the keyboard and VoiceOver.
    func adjustVolume(by steps: Int) {
        guard let volume else {
            return
        }
        setVolume(DisplayControlsLevel.stepped(volume, by: steps))
    }

    /// Mutes or unmutes the output. The state shown afterwards is the one read back.
    func setMuted(_ muted: Bool) {
        guard let device, canMute else {
            return
        }
        OutputVolume.setMuted(muted, device)
        isMuted = OutputVolume.isMuted(device) ?? false
    }

    private func clear() {
        device = nil
        plan = .unsupported
        volume = nil
        isMuted = false
        canMute = false
        outputName = nil
    }

    // MARK: Hub

    /// Reads the state once more and starts the listeners when the hub opens, and stops them
    /// when it closes.
    func hubVisibilityDidChange(isOpen: Bool) {
        if isOpen {
            refresh()
            listener.start { [weak self] in
                self?.refresh()
            }
        } else {
            listener.stop()
        }
    }

    /// The Overview card: the volume as a ring, or the word "Muted" while muted. No name.
    var tile: HubTile? {
        guard let volume else {
            return nil
        }
        if isMuted {
            return HubTile(
                symbol: "speaker.slash.fill",
                title: Text("Volume"),
                value: String(localized: "Muted")
            )
        }
        return HubTile(
            symbol: "speaker.wave.2.fill",
            title: Text("Volume"),
            value: String(DisplayControlsLevel.percent(volume)),
            unit: Text(verbatim: "%"),
            fraction: volume
        )
    }

    /// The pill beside the notch while the output is muted. No name.
    var statusPill: HubStatusPill? {
        guard isMuted else {
            return nil
        }
        return HubStatusPill(
            symbol: "speaker.slash.fill",
            text: String(localized: "Muted"),
            accessibilityLabel: Text("Muted")
        )
    }

    func makeBody(host _: any HubHost) -> AnyView {
        AnyView(DisplayControlsBodyView(runtime: self))
    }

    /// Stops the listeners and releases the state.
    func shutDown() {
        listener.stop()
        clear()
        brightness = nil
        brightnessDisplay = nil
    }
}
