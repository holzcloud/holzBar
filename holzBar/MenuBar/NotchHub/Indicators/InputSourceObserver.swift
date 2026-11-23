//
//  InputSourceObserver.swift
//  holzBar
//

import AppKit
import Carbon.HIToolbox

/// The keyboard input source in use, as plain values read from the system. They stay in memory:
/// the name and the icon are never stored, exported or logged.
struct InputSourceInfo: Equatable, Sendable {
    /// The source's identifier, such as `com.apple.keylayout.German`.
    let id: String
    /// The name in the user's language, such as "German".
    let localizedName: String
    /// The languages the source types, most specific first, such as `["de"]`; empty when it has none.
    let languages: [String]
    /// The icon image file of the source, or `nil` for a plain keyboard layout, which has none.
    /// Only a file URL, because the system gives one.
    let iconURL: URL?
}

/// Follows the keyboard input source through the system's two distributed notifications and reads
/// it through the Text Input Sources API (D-09).
///
/// Nothing polls: the selected-source notification, delivered immediately, triggers the caller's
/// own read of ``current()``, and the enabled-sources notification tells it to count again. The
/// observer exists only while the Input source switch is on, asks no permission and holds no
/// name. The Text Input Sources calls belong on the main thread, which this type is isolated to.
@MainActor
final class InputSourceObserver: NSObject {
    /// What changed.
    enum Change: Sendable {
        /// The selected input source changed.
        case selected
        /// The set of enabled input sources changed.
        case enabledSources
    }

    private var onChange: (@MainActor (Change) -> Void)?

    /// Whether the observer is listening.
    var isRunning: Bool {
        onChange != nil
    }

    /// Starts listening. A second call replaces the handler and listens once.
    func start(onChange: @escaping @MainActor (Change) -> Void) {
        stop()
        self.onChange = onChange
        let center = DistributedNotificationCenter.default()
        // Delivered immediately, also while another app is active, or a switch made in the
        // background would arrive late and look like a second one.
        center.addObserver(
            self,
            selector: #selector(selectedSourceDidChange(_:)),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(enabledSourcesDidChange(_:)),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    /// Stops listening. Safe to call when it is not.
    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        onChange = nil
    }

    @objc private func selectedSourceDidChange(_: Notification) {
        onChange?(.selected)
    }

    @objc private func enabledSourcesDidChange(_: Notification) {
        onChange?(.enabledSources)
    }

    // MARK: Reading

    /// The input source in use now, or `nil` when the system reports none.
    static func current() -> InputSourceInfo? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let id = stringProperty(of: source, key: kTISPropertyInputSourceID) else {
            return nil
        }
        let name = stringProperty(of: source, key: kTISPropertyLocalizedName) ?? ""
        var languages = [String]()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            languages = (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
        }
        // Only the icon image file: the Carbon icon reference would need a deprecated NSImage
        // initializer, and a plain keyboard layout has no file, so the caller draws a symbol.
        var iconURL: URL?
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
            iconURL = url.isFileURL ? url : nil
        }
        return InputSourceInfo(id: id, localizedName: name, languages: languages, iconURL: iconURL)
    }

    /// How many keyboard input sources are enabled and can be selected: the keyboard layouts and the
    /// input methods' modes in the user's list. Zero when the system reports none.
    static func enabledCount() -> Int {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return 0
        }
        return CFArrayGetCount(list)
    }

    private static func stringProperty(of source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
