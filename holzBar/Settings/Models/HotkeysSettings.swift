//
//  HotkeysSettings.swift
//  holzBar
//

import Foundation
import Observation
import OSLog

/// Model for the app's Hotkeys settings.
///
/// Every hotkey is stored in the `Hotkeys` setting under its target's storage key
/// (``HotkeyTarget/storageKey``): one per action, under Ice's names, and one for each
/// layout profile and menu bar item the user gave a hotkey. Saving changes only its own key,
/// so keys of other versions survive.
@MainActor
@Observable
final class HotkeysSettings {
    /// The app's hotkey registry.
    @ObservationIgnored let registry = HotkeyRegistry()

    /// The hotkeys of holzBar's actions, one for each action.
    let hotkeys = HotkeyAction.allCases.map { action in
        Hotkey(target: .action(action))
    }

    /// The hotkeys that apply a layout profile or open a menu bar item, in the order they
    /// were created.
    private(set) var dynamicHotkeys = [Hotkey]()

    /// Encoder for properties.
    @ObservationIgnored private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored private let decoder = JSONDecoder()

    /// Observers that save each hotkey when it changes, by target.
    @ObservationIgnored private var observers = [HotkeyTarget: ObservationLoop]()

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        for hotkey in hotkeys {
            hotkey.performSetup(with: appState)
        }
        loadInitialState()
        for hotkey in hotkeys + dynamicHotkeys {
            observe(hotkey)
        }
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        guard
            let dictionary = Defaults.dictionary(forKey: .hotkeys) as? [String: Data],
            !dictionary.isEmpty
        else {
            return
        }
        for hotkey in hotkeys {
            guard let data = dictionary[hotkey.target.storageKey] else {
                continue
            }
            if let keyCombination = decodeKeyCombination(data, for: hotkey.target) {
                hotkey.keyCombination = keyCombination
            }
        }
        for key in dictionary.keys.sorted() {
            guard
                let target = HotkeyTarget(storageKey: key),
                target.isDynamic,
                let data = dictionary[key],
                let keyCombination = decodeKeyCombination(data, for: target)
            else {
                continue
            }
            let hotkey = Hotkey(target: target)
            if let appState {
                hotkey.performSetup(with: appState)
            }
            hotkey.keyCombination = keyCombination
            dynamicHotkeys.append(hotkey)
        }
    }

    /// Decodes a stored key combination, or returns `nil` for none or an invalid one.
    private func decodeKeyCombination(_ data: Data, for target: HotkeyTarget) -> KeyCombination? {
        do {
            // An invalid stored combination (a key code out of range, unknown modifier
            // bits) fails to decode and is ignored (jordanbaird/Ice#985).
            guard let keyCombination = try decoder.decode(KeyCombination?.self, from: data) else {
                return nil
            }
            guard !keyCombination.isSystemReserved else {
                Logger.hotkeys.error("Ignoring stored hotkey of \(target.logDescription, privacy: .public): reserved by the system")
                return nil
            }
            return keyCombination
        } catch {
            Logger.serialization.error("Ignoring stored hotkey of \(target.logDescription, privacy: .public): \(error, privacy: .private)")
            return nil
        }
    }

    /// Saves the hotkey whenever its key combination changes.
    private func observe(_ hotkey: Hotkey) {
        let target = hotkey.target
        observers[target] = ObservationLoop.observe { hotkey.keyCombination } onChange: { [weak self] keyCombination in
            self?.save(keyCombination, for: target)
        }
    }

    /// Saves the key combination of the hotkey with the given target.
    ///
    /// A profile or an item whose hotkey was cleared loses its key, so nothing is left behind.
    private func save(_ keyCombination: KeyCombination?, for target: HotkeyTarget) {
        do {
            let data = try encoder.encode(keyCombination)
            withMutableCopy(of: Defaults.dictionary(forKey: .hotkeys) ?? [:]) { dictionary in
                if keyCombination == nil, target.isDynamic {
                    dictionary[target.storageKey] = nil
                } else {
                    dictionary[target.storageKey] = data
                }
                Defaults.set(dictionary, forKey: .hotkeys)
            }
        } catch {
            Logger.serialization.error("Error encoding hotkey: \(error, privacy: .private)")
        }
    }

    /// Returns the hotkey with the given action.
    func hotkey(withAction action: HotkeyAction) -> Hotkey? {
        hotkeys.first { $0.action == action }
    }

    /// Returns the hotkey of a profile or an item, if it has one.
    func existingHotkey(for target: HotkeyTarget) -> Hotkey? {
        if case .action(let action) = target {
            return hotkey(withAction: action)
        }
        return dynamicHotkeys.first { $0.target == target }
    }

    /// Returns the hotkey for the given target, creating one without a key combination for
    /// a profile or an item that has none yet.
    func hotkey(for target: HotkeyTarget) -> Hotkey {
        if let existing = existingHotkey(for: target) {
            return existing
        }
        let hotkey = Hotkey(target: target)
        if let appState {
            hotkey.performSetup(with: appState)
        }
        dynamicHotkeys.append(hotkey)
        observe(hotkey)
        return hotkey
    }

    /// Sets the key combination of the hotkey for the given target.
    func setKeyCombination(_ keyCombination: KeyCombination?, for target: HotkeyTarget) {
        hotkey(for: target).keyCombination = keyCombination
    }

    /// Removes the hotkey of a profile or an item and its stored key.
    func removeHotkey(for target: HotkeyTarget) {
        guard target.isDynamic else {
            return
        }
        if let index = dynamicHotkeys.firstIndex(where: { $0.target == target }) {
            let hotkey = dynamicHotkeys.remove(at: index)
            observers[target] = nil
            hotkey.disable()
        }
        withMutableCopy(of: Defaults.dictionary(forKey: .hotkeys) ?? [:]) { dictionary in
            guard dictionary[target.storageKey] != nil else {
                return
            }
            dictionary[target.storageKey] = nil
            Defaults.set(dictionary, forKey: .hotkeys)
        }
    }

    /// Moves the hotkey of one target to another, for a renamed profile.
    func moveHotkey(from oldTarget: HotkeyTarget, to newTarget: HotkeyTarget) {
        guard oldTarget != newTarget else {
            return
        }
        let keyCombination = existingHotkey(for: oldTarget)?.keyCombination
        removeHotkey(for: oldTarget)
        if let keyCombination {
            setKeyCombination(keyCombination, for: newTarget)
        }
    }
}
