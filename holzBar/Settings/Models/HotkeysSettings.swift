//
//  HotkeysSettings.swift
//  holzBar
//

import Foundation
import Observation
import OSLog

/// Model for the app's Hotkeys settings.
@MainActor
@Observable
final class HotkeysSettings {
    /// The app's hotkey registry.
    @ObservationIgnored let registry = HotkeyRegistry()

    /// The app's hotkeys.
    let hotkeys = HotkeyAction.allCases.map { action in
        Hotkey(action: action)
    }

    /// Encoder for properties.
    @ObservationIgnored private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored private let decoder = JSONDecoder()

    /// Observers that save each hotkey when it changes.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        for hotkey in hotkeys {
            hotkey.performSetup(with: appState)
        }
        loadInitialState()
        configureObservers()
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
            guard let data = dictionary[hotkey.action.rawValue] else {
                continue
            }
            do {
                // An invalid stored combination (a key code out of range, unknown modifier
                // bits) fails to decode and is ignored (jordanbaird/Ice#985).
                if let keyCombination = try decoder.decode(KeyCombination?.self, from: data) {
                    guard !keyCombination.isSystemReserved else {
                        Logger.hotkeys.error("Ignoring stored hotkey \(hotkey.action.rawValue, privacy: .public): reserved by the system")
                        continue
                    }
                    hotkey.keyCombination = keyCombination
                }
            } catch {
                Logger.serialization.error("Ignoring stored hotkey \(hotkey.action.rawValue, privacy: .public): \(error, privacy: .private)")
            }
        }
    }

    /// Saves each hotkey whenever its key combination changes.
    private func configureObservers() {
        observers = hotkeys.map { hotkey in
            ObservationLoop.observe { hotkey.keyCombination } onChange: { [weak self] keyCombination in
                self?.save(keyCombination, for: hotkey.action)
            }
        }
    }

    /// Saves the key combination of the hotkey with the given action.
    private func save(_ keyCombination: KeyCombination?, for action: HotkeyAction) {
        do {
            let data = try encoder.encode(keyCombination)
            withMutableCopy(of: Defaults.dictionary(forKey: .hotkeys) ?? [:]) { dictionary in
                dictionary[action.rawValue] = data
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
}
