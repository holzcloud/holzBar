//
//  DisplayControlsRuntime.swift
//  holzBar
//

import CoreAudio
import Foundation
import Observation
import SwiftUI

/// The running part of the Display controls module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. It reads the volume
/// of the default sound output when the hub opens and when its tab appears, and sets it; the
/// level it shows is always the one read back from the system, never the one requested. It
/// logs nothing that names a device.
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

    /// The device the volume was read from.
    @ObservationIgnored private var device: AudioObjectID?

    /// Creates the runtime. It has nothing to start yet: the state is read when the hub opens.
    init(appState _: AppState) {}

    /// Reads the default output's plan and level again.
    func refresh() {
        guard let output = OutputVolume.current() else {
            device = nil
            plan = .unsupported
            volume = nil
            return
        }
        device = output.device
        plan = output.plan
        volume = OutputVolume.volume(of: output.device, plan: output.plan)
    }

    /// Sets the level. The level shown afterwards is the one read back, not the argument.
    func setVolume(_ value: Double) {
        guard let device, plan != .unsupported else {
            return
        }
        OutputVolume.setVolume(value, of: device, plan: plan)
        volume = OutputVolume.volume(of: device, plan: plan)
    }

    // MARK: Hub

    /// Reads the state once more when the hub opens.
    func hubVisibilityDidChange(isOpen: Bool) {
        if isOpen {
            refresh()
        }
    }

    func makeBody(host _: any HubHost) -> AnyView {
        AnyView(DisplayControlsBodyView(runtime: self))
    }

    /// Releases the state.
    func shutDown() {
        device = nil
        plan = .unsupported
        volume = nil
    }
}
