//
//  IndicatorsSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the Indicators module's own settings: whether a change of the keyboard input source
/// flashes in the closed notch, and for how long, and whether a change of the volume does. Each
/// saves itself in its `didSet`.
///
/// The running module (``IndicatorsRuntime``) follows ``showsInputSource`` and starts the system's
/// input source notifications only while it is on, and follows ``showsVolumeBrightness`` and starts
/// its volume listener only while that is on, so nothing observes while they are off. It follows
/// ``replacesSystemDisplay`` as well and keeps the media-key tap only while that is on too and holzBar
/// holds Accessibility.
@MainActor
@Observable
final class IndicatorsSettings {
    /// The identifier of the Indicators module in ``ModuleCatalog``.
    static let moduleID = IndicatorLook.moduleID

    /// A Boolean value that indicates whether a change of the input source flashes in the notch.
    /// Off by default.
    var showsInputSource = false {
        didSet {
            guard showsInputSource != oldValue else {
                return
            }
            Defaults.set(showsInputSource, forKey: .indicatorsInputSource)
        }
    }

    /// How long the input source flash stays, in seconds: one of
    /// ``DesignTokens/Indicator/inputSourceDurations``, 1.5 by default. The picker offers only
    /// those; what is stored is snapped to the nearest one, and whoever reads it snaps it again
    /// with ``IndicatorLook/inputSourceDuration(_:)``.
    var inputSourceDuration = DesignTokens.Indicator.inputSourceDefaultDuration {
        didSet {
            guard inputSourceDuration != oldValue else {
                return
            }
            Defaults.set(inputSourceDuration, forKey: .indicatorsInputSourceDuration)
        }
    }

    /// A Boolean value that indicates whether a change of the volume shows in the closed notch. Off
    /// by default.
    var showsVolumeBrightness = false {
        didSet {
            guard showsVolumeBrightness != oldValue else {
                return
            }
            Defaults.set(showsVolumeBrightness, forKey: .indicatorsVolumeBrightness)
        }
    }

    /// A Boolean value that indicates whether holzBar takes the volume and brightness keys it can
    /// handle and shows its own display instead of the system's. Off by default; a private-interface
    /// switch, stored on this Mac only. Turning it on is the only moment holzBar asks for
    /// Accessibility.
    var replacesSystemDisplay = false {
        didSet {
            guard replacesSystemDisplay != oldValue else {
                return
            }
            Defaults.set(replacesSystemDisplay, forKey: .indicatorsReplacesSystemDisplay)
        }
    }

    /// Loads the stored settings. The duration is clamped to its range and snapped to the nearest
    /// choice, because the defaults can hold anything.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .indicatorsInputSource, assign: &showsInputSource)
        Defaults.ifPresent(key: .indicatorsVolumeBrightness, assign: &showsVolumeBrightness)
        Defaults.ifPresent(key: .indicatorsReplacesSystemDisplay, assign: &replacesSystemDisplay)
        Defaults.ifPresent(key: .indicatorsInputSourceDuration) { (stored: Double) in
            let clamped = Defaults.Key.indicatorsInputSourceDuration.clamped(
                stored,
                fallback: DesignTokens.Indicator.inputSourceDefaultDuration
            )
            inputSourceDuration = IndicatorLook.inputSourceDuration(clamped)
        }
    }
}
