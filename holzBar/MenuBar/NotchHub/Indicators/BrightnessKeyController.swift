//
//  BrightnessKeyController.swift
//  holzBar
//

import CoreGraphics
import Foundation
import Observation

/// Performs a taken brightness key on the display under the pointer (Phase 96, D-06, D-21, D-22,
/// DISP-03).
///
/// It owns no private interface. The built-in display is changed through
/// ``DisplayServicesBrightness`` and nothing else, behind a ``PrivateFeatureGate`` of its own that
/// follows Display controls' Brightness switch and the three-failures rule. Nothing here loads a
/// framework or looks a symbol up, and neither wrapper file was changed for it (D-22 widens the
/// exception's wording to a second caller, no more). While the Brightness switch is off or the
/// Display controls module is off, the framework is not loaded and the keys pass.
///
/// The key is already consumed when ``step(_:display:quarter:)`` runs, so a failed step shows
/// nothing and counts against the gate; the third failure in a row switches the part off for the
/// session, the snapshot of the tap is built again and the keys pass from then on. The controller
/// lives only while the media-key tap does and keeps nothing about a display but numbers.
@MainActor
@Observable
final class BrightnessKeyController {
    /// Whether the built-in display's part may run: follows the Brightness switch, the result of
    /// loading the wrapper and the failures counted here.
    private(set) var builtInGate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// Called when what the tap may take changed (a gate switched itself off, an answer arrived).
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: Switches

    /// Whether the Display controls module is on.
    var isDisplayControlsOn: Bool {
        appState?.modules.isEnabled(DisplayControlsRuntime.identifier) ?? false
    }

    /// Whether Display controls' Brightness switch is on and the module with it.
    var isBuiltInSwitchOn: Bool {
        isDisplayControlsOn && appState?.settings.displayControls.showsBrightness == true
    }

    /// Follows the Brightness switch. The wrapper is loaded the first time the switch is on while
    /// the keys replace the system's, never before and never with the switch off.
    func refreshGates() {
        var gate = builtInGate
        if PrivateFeatureGate.shouldLoad(isEnabled: isBuiltInSwitchOn) {
            gate.setEnabled(true, load: DisplayServicesBrightness.load())
        } else {
            gate.setEnabled(false, load: .loaded)
        }
        if gate != builtInGate {
            builtInGate = gate
        }
    }

    /// Whether the part that the user's switches leave on has switched itself off: the framework
    /// or a function is missing, or three calls failed in a row. `false` while the part is simply
    /// off.
    var hasSwitchedItselfOff: Bool {
        guard isBuiltInSwitchOn, case .unavailable(let reason) = builtInGate.state else {
            return false
        }
        return reason != .switchedOff
    }

    // MARK: Targets

    /// What a brightness key would change on a display, for the snapshot of the tap.
    func target(for display: CGDirectDisplayID) -> MediaKeyRule.Target {
        guard isBuiltInSwitchOn, builtInGate.isAvailable, DisplayServicesBrightness.canChange(display) else {
            return CGDisplayIsBuiltin(display) != 0 ? .builtIn(canChange: false) : .unknown
        }
        return .builtIn(canChange: true)
    }

    // MARK: Steps

    /// Moves the brightness of a display by one step of a taken key and returns the level the
    /// display then reports, from 0 to 1, or `nil` when nothing changed (nothing is shown then).
    ///
    /// While the hub is open the Display controls runtime's own setters do it, so one writer talks
    /// to a display and the open tab follows; otherwise the controller's own path does.
    func step(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) async -> Double? {
        guard code == .brightnessUp || code == .brightnessDown else {
            return nil
        }
        if let level = stepThroughOpenHub(code, display: display, quarter: quarter) {
            return level
        }
        return stepBuiltIn(code, display: display, quarter: quarter)
    }

    /// Stops everything: nothing is kept.
    func shutDown() {
        onChange = nil
    }

    /// The Display controls runtime is running with its tab open: its setters move the display.
    private func stepThroughOpenHub(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) -> Double? {
        guard
            let hub = appState?.notchHub,
            hub.isOpen,
            let runtime = hub.runtime(DisplayControlsRuntime.self),
            let shown = runtime.displays.first(where: { $0.id == display && $0.canChange })?.value
        else {
            return nil
        }
        runtime.setBrightness(MediaKeyRule.next(level: shown, code: code, quarter: quarter), for: display)
        return runtime.displays.first { $0.id == display }?.value
    }

    /// The built-in display: read, write the step, read back; never below the 2 % floor.
    private func stepBuiltIn(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) -> Double? {
        guard isBuiltInSwitchOn, builtInGate.isAvailable, DisplayServicesBrightness.canChange(display) else {
            return nil
        }
        guard let current = DisplayServicesBrightness.read(display) else {
            recordBuiltInFailure()
            return nil
        }
        let next = MediaKeyRule.next(level: current, code: code, quarter: quarter)
        guard DisplayServicesBrightness.write(next, to: display), let readBack = DisplayServicesBrightness.read(display) else {
            recordBuiltInFailure()
            return nil
        }
        var gate = builtInGate
        gate.recordSuccess()
        if gate != builtInGate {
            builtInGate = gate
        }
        return readBack
    }

    /// Counts a failed call. The third in a row switches the part off for the session, and the
    /// tap's snapshot is built again so the keys pass.
    private func recordBuiltInFailure() {
        builtInGate.recordFailure()
        if !builtInGate.isAvailable {
            onChange?()
        }
    }
}
