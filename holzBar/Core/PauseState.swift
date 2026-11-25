//
//  PauseState.swift
//  holzBar
//

/// Whether the user paused holzBar on macOS 27 (the "Pause holzBar" command, D-14).
///
/// While paused, the concealment target is empty, so every menu bar item is shown. The state is
/// not persisted: quitting or relaunching holzBar resumes the hiding, so a pause can never
/// outlive the session.
nonisolated struct PauseState: Equatable, Sendable {
    /// Whether holzBar is paused now.
    private(set) var isPaused = false

    /// Pauses a running holzBar and resumes a paused one.
    ///
    /// - Returns: Whether holzBar is paused afterwards.
    @discardableResult
    mutating func toggle() -> Bool {
        isPaused.toggle()
        return isPaused
    }

    /// The concealment target to apply: empty while paused, otherwise `sets` unchanged.
    func target(_ sets: [Set<String>]) -> [Set<String>] {
        isPaused ? [] : sets
    }
}
