//
//  DisplayServicesBrightness.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// The one file of the app that names the private display framework and its three functions.
///
/// This is private API: Apple does not document it and may change it with any macOS update.
/// It is here because macOS has no public way to read or set a display's brightness, and the
/// maintainer agreed to it for the Display controls module only (decision D-08). What protects
/// the app:
/// - The framework is loaded with `dlopen` and the functions looked up with `dlsym` the first
///   time they are needed, never at launch and never through a link, so the app starts and runs
///   when the framework is gone or changed. Nothing here runs while the module's Brightness
///   setting is off, because the caller never reaches this file then.
/// - A function is called only when all three were found. The prototypes are those the spike
///   measured on macOS 27.2: the answer to "can change" is a Boolean, and the other two return
///   0 on success.
/// - A display is read before it is written, and every value written is kept between 2 and 100
///   percent.
/// - Every failure is a `nil` or `false`; ``PrivateFeatureGate`` counts them and switches the
///   part off by itself.
///
/// The file keeps no observer, starts no timer and logs nothing.
@MainActor
enum DisplayServicesBrightness {
    private typealias CanChangeFunction = @convention(c) (UInt32) -> Bool
    private typealias GetFunction = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (UInt32, Float) -> Int32

    private struct Functions {
        let canChange: CanChangeFunction
        let get: GetFunction
        let set: SetFunction
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    /// The outcome of the one attempt to load, kept for the rest of the session.
    private static var outcome: (result: PrivateFeatureGate.LoadResult, functions: Functions?)?

    /// The displays that were read successfully in this session. A display is written only
    /// after it was read.
    private static var readDisplays = Set<CGDirectDisplayID>()

    /// Loads the framework and looks up the three functions, the first time only; later calls
    /// return the same result.
    static func load() -> PrivateFeatureGate.LoadResult {
        if let outcome {
            return outcome.result
        }
        let attempt = resolve()
        outcome = attempt
        return attempt.result
    }

    /// Whether macOS can change the brightness of a display from here. `false` when the
    /// functions are not loaded.
    static func canChange(_ display: CGDirectDisplayID) -> Bool {
        guard let functions = outcome?.functions else {
            return false
        }
        return functions.canChange(display)
    }

    /// The brightness of a display from 0 to 1, or `nil` when the call fails or answers with a
    /// value that is not a level.
    static func read(_ display: CGDirectDisplayID) -> Double? {
        guard let functions = outcome?.functions else {
            return nil
        }
        var level: Float = -1
        guard functions.get(display, &level) == 0, level.isFinite, (0...1).contains(level) else {
            return nil
        }
        readDisplays.insert(display)
        return Double(level)
    }

    /// Sets the brightness of a display, kept between 2 and 100 percent. Returns `false` and
    /// does nothing for a display that was not read successfully before.
    static func write(_ value: Double, to display: CGDirectDisplayID) -> Bool {
        guard let functions = outcome?.functions, readDisplays.contains(display) else {
            return false
        }
        let level = Float(DisplayControlsLevel.clampedBrightness(value))
        return functions.set(display, level) == 0
    }

    private static func resolve() -> (result: PrivateFeatureGate.LoadResult, functions: Functions?) {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            return (.frameworkMissing, nil)
        }
        guard
            let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness"),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let set = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            return (.symbolMissing, nil)
        }
        let functions = Functions(
            canChange: unsafeBitCast(canChange, to: CanChangeFunction.self),
            get: unsafeBitCast(get, to: GetFunction.self),
            set: unsafeBitCast(set, to: SetFunction.self)
        )
        return (.loaded, functions)
    }
}
