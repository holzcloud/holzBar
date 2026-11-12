//
//  LayoutUndo.swift
//  holzBar
//

import SwiftUI

/// The undo history of the layout: every change of the arrangement, made in Settings or in the
/// menu bar, can be taken back from the undo toast, the Undo button in Layout and ⌘Z in the
/// Settings window (D-03, D-14, D-15).
///
/// It lives as long as the app, in memory only, and holds at most twenty changes. Nothing runs
/// while nothing changes: no timer, no observer (D-33).
@MainActor
@Observable
final class LayoutUndo {
    /// Where a toast shows: at the bottom of the Settings window, of the floating appearance
    /// editor, or near the menu bar.
    enum Place: Equatable {
        case settings
        case appearanceEditor
        case menuBar
    }

    /// One change that can be undone.
    struct Change: Identifiable {
        let id = UUID()
        /// The sentence the toast shows, which says what happened (D-13).
        let sentence: String
        /// The name of the change in the Edit menu ("Undo <name>").
        let actionName: String
        /// The change that takes the undo back again (the redo), built from the state now,
        /// before `perform` runs; `nil` when there is nothing to take back.
        let inverse: @MainActor () -> Change?
        /// Does the undo and returns whether everything is back.
        let perform: @MainActor () async -> Bool
        /// Runs when the change leaves the history without being undone, and at quit.
        var onDiscard: (@MainActor () -> Void)?
    }

    /// What the toast shows now.
    struct ToastContent: Equatable, Identifiable {
        let id: UUID
        let sentence: String
        /// Whether the toast reports an undo that could not put everything back (D-17).
        let isFailure: Bool
        let place: Place
    }

    /// The one wait on macOS 27 after an undo, before holzBar reads the items again: macOS
    /// arranges per application and needs a moment (D-17). One deadline, no polling.
    static let settleDelay27 = Duration.seconds(2)

    /// The toast that shows now, if any.
    private(set) var toast: ToastContent?

    /// Whether there is a change to undo.
    private(set) var canUndo = false

    @ObservationIgnored private var history = UndoHistory<Change>()
    @ObservationIgnored private weak var appState: AppState?

    /// The Settings window's undo manager, which mirrors the history for ⌘Z and ⇧⌘Z (D-15).
    @ObservationIgnored private weak var windowUndoManager: UndoManager?
    /// One registration target per change, so a change's registration can be taken out alone.
    @ObservationIgnored private var tokens = [UUID: UndoToken]()
    /// The changes registered on the window as redos, by identifier.
    @ObservationIgnored private var redoChanges = [UUID: Change]()
    /// The panel under the menu bar, made at the first toast there (D-33).
    @ObservationIgnored private var panel: UndoToastPanel?

    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    /// The arrangement as it is now, to be put back by an undo.
    func beforeSnapshot() -> LayoutSnapshot {
        guard let appState else {
            return LayoutSnapshot(date: .now, reason: .manual, itemSections: [:], applicationSections: [:])
        }
        return appState.snapshots.currentSnapshot(reason: .manual)
    }

    /// Adds a change as the newest one and shows its toast at the given place.
    func record(_ change: Change, place: Place) {
        // A new change ends what could be redone, in the window's undo manager as here.
        redoChanges.removeAll()
        push(change)
        setToast(ToastContent(id: UUID(), sentence: change.sentence, isFailure: false, place: resolved(place)))
        LayoutBarItemView.announce(change.sentence)
    }

    /// Mirrors the history on the Settings window's undo manager, oldest first, so ⌘Z, ⇧⌘Z
    /// and the Edit menu act on the same changes as the toast (D-15).
    func settingsWindowDidAppear(_ undoManager: UndoManager) {
        guard undoManager !== windowUndoManager else {
            return
        }
        windowUndoManager = undoManager
        for change in history.entries {
            register(change, on: undoManager)
        }
    }

    /// Records a change after which the sections of `before` are to be put back: Apply, Tidy
    /// Up, a suggestion, a profile (D-15). The order within a section is not part of it.
    func recordArrangementChange(_ sentence: String, before: LayoutSnapshot, place: Place) {
        record(arrangementChange(sentence, before: before), place: place)
    }

    /// Undoes the newest change: the toast's button and the Undo button in Layout.
    func undo() {
        guard let change = history.popNewest() else {
            return
        }
        canUndo = !history.isEmpty
        // ⌘Z must not undo it a second time.
        unregister(change.id)
        let place = toast?.place ?? .settings
        setToast(nil)
        Task {
            let isRestored = await change.perform()
            report(isRestored: isRestored, place: place)
        }
    }

    /// Hides the toast with the given identifier, if it still shows.
    func dismissToast(id: UUID) {
        if toast?.id == id {
            setToast(nil)
        }
    }

    /// Records a deletion that acted at once: Undo puts the thing back where it was (D-04,
    /// D-16).
    ///
    /// - Parameters:
    ///   - restore: Puts the deleted thing back at its place.
    ///   - deleteAgain: Deletes it again (the redo).
    ///   - onDiscard: Lets go of what the deletion kept for its undo, for example a group's
    ///     image, once the deletion can no longer be undone.
    func recordDeletion(
        _ sentence: String,
        place: Place,
        restore: @escaping @MainActor () -> Void,
        deleteAgain: @escaping @MainActor () -> Void,
        onDiscard: (@MainActor () -> Void)? = nil
    ) {
        record(
            Self.deletionChange(sentence, restore: restore, deleteAgain: deleteAgain, onDiscard: onDiscard),
            place: place
        )
    }

    /// Empties the history at quit: every change lets go of what it kept.
    func discardAll() {
        for change in history.removeAll() {
            unregister(change.id)
            change.onDiscard?()
        }
        redoChanges.removeAll()
        canUndo = false
    }

    /// Takes a change out of the history without running it, for example when the notice it
    /// belongs to was undone on its own.
    func forget(id: UUID) {
        guard history.remove(id: id) != nil else {
            return
        }
        unregister(id)
        canUndo = !history.isEmpty
    }

    /// Puts the sections of `before` back and tells whether everything is back: the undo of
    /// Apply, Tidy Up, a suggestion and a profile (D-15).
    func restoreArrangement(_ before: LayoutSnapshot) async -> Bool {
        guard let appState else {
            return true
        }
        appState.snapshots.willUndo()
        let layout = appState.automation.removingControlledItems(from: LayoutProfile(
            name: "",
            itemSections: before.itemSections,
            applicationSections: before.applicationSections,
            knownApplications: before.knownApplications
        ))
        await appState.profiles.applyLayout(of: layout)?.value
        if #available(macOS 27.0, *) {
            appState.automation.itemsWereArrangedByHand()
            try? await Task.sleep(for: Self.settleDelay27)
            await appState.itemManager.cacheItemsRegardless()
        }
        return ArrangementUndo.isRestored(wanted: before, now: appState.snapshots.currentSnapshot(reason: .manual))
    }

    // MARK: Private

    private static func deletionChange(
        _ sentence: String,
        restore: @escaping @MainActor () -> Void,
        deleteAgain: @escaping @MainActor () -> Void,
        onDiscard: (@MainActor () -> Void)?
    ) -> Change {
        Change(
            sentence: sentence,
            actionName: String(localized: "Delete"),
            inverse: {
                // The redo deletes again; its own undo restores again.
                Change(
                    sentence: sentence,
                    actionName: String(localized: "Delete"),
                    inverse: {
                        deletionChange(sentence, restore: restore, deleteAgain: deleteAgain, onDiscard: onDiscard)
                    },
                    perform: {
                        deleteAgain()
                        return true
                    },
                    onDiscard: nil
                )
            },
            perform: {
                restore()
                return true
            },
            onDiscard: onDiscard
        )
    }

    /// Shows the toast and puts the menu bar panel up or away to match.
    private func setToast(_ content: ToastContent?) {
        toast = content
        guard let appState else {
            return
        }
        if content?.place == .menuBar {
            let panel = panel ?? UndoToastPanel(undo: self)
            self.panel = panel
            panel.show(for: appState)
        } else {
            panel?.hide()
        }
    }

    /// The place a toast shows: a host that is not on screen hands it to the menu bar.
    private func resolved(_ place: Place) -> Place {
        guard let appState else {
            return place
        }
        switch place {
        case .settings where !appState.navigationState.isSettingsPresented:
            return .menuBar
        case .appearanceEditor where !appState.menuBarManager.appearanceEditorPanel.isVisible:
            return .menuBar
        default:
            return place
        }
    }

    /// Pushes a change into the history and onto the window's undo manager; a change that
    /// falls out of the history lets go of what it keeps.
    private func push(_ change: Change) {
        for dropped in history.push(change) {
            unregister(dropped.id)
            dropped.onDiscard?()
        }
        canUndo = !history.isEmpty
        if let windowUndoManager {
            register(change, on: windowUndoManager)
        }
    }

    private func register(_ change: Change, on manager: UndoManager) {
        let token = tokens[change.id] ?? UndoToken(owner: self, changeID: change.id)
        tokens[change.id] = token
        manager.registerUndo(withTarget: token) { token in
            MainActor.assumeIsolated {
                token.owner?.undoFromWindow(token.changeID)
            }
        }
        manager.setActionName(change.actionName)
    }

    private func unregister(_ id: UUID) {
        if let token = tokens.removeValue(forKey: id) {
            windowUndoManager?.removeAllActions(withTarget: token)
        }
    }

    /// ⌘Z, ⇧⌘Z or the Edit menu: undoes the change, and registers its inverse as the redo
    /// (while undoing) or as the newest undoable change (while redoing).
    private func undoFromWindow(_ id: UUID) {
        guard let change = history.remove(id: id) ?? redoChanges.removeValue(forKey: id) else {
            return
        }
        tokens[id] = nil
        canUndo = !history.isEmpty
        let place = toast?.place ?? .settings
        setToast(nil)
        // The inverse reads the state before anything moves.
        if let inverse = change.inverse(), let manager = windowUndoManager {
            if manager.isUndoing {
                redoChanges[inverse.id] = inverse
                register(inverse, on: manager)
            } else if manager.isRedoing {
                push(inverse)
                setToast(ToastContent(id: UUID(), sentence: inverse.sentence, isFailure: false, place: resolved(place)))
            }
        }
        Task {
            let isRestored = await change.perform()
            report(isRestored: isRestored, place: place)
        }
    }

    private func arrangementChange(_ sentence: String, before: LayoutSnapshot) -> Change {
        Change(
            sentence: sentence,
            actionName: sentence,
            inverse: { [weak self] in
                guard let self else {
                    return nil
                }
                return arrangementChange(sentence, before: beforeSnapshot())
            },
            perform: { [weak self] in
                await self?.restoreArrangement(before) ?? true
            }
        )
    }

    /// Shows a toast when an undo could not put everything back; otherwise nothing (D-17).
    private func report(isRestored: Bool, place: Place) {
        guard !isRestored else {
            return
        }
        let sentence = String(localized: "Some items could not be put back.")
        setToast(ToastContent(id: UUID(), sentence: sentence, isFailure: true, place: resolved(place)))
        LayoutBarItemView.announce(sentence)
    }
}

// MARK: - The toast

extension View {
    /// Shows the undo toast of the history at the bottom of this view while its place is this
    /// one: 5 s, and as long as the pointer rests on it (D-03).
    func holzBarUndoToast(_ undo: LayoutUndo, place: LayoutUndo.Place) -> some View {
        modifier(UndoToastModifier(undo: undo, place: place))
    }
}

private struct UndoToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let undo: LayoutUndo
    let place: LayoutUndo.Place

    func body(content: Content) -> some View {
        let shown = undo.toast.flatMap { $0.place == place ? $0 : nil }
        content
            .overlay(alignment: .bottom) {
                if shown != nil {
                    UndoToastView(undo: undo, place: place)
                        .padding(.bottom, HolzBarTheme.Spacing.lg)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
                value: shown
            )
    }
}

/// The undo toast of one place: the sentence with Undo, or the failure report. It goes after
/// 5 s, and stays while the pointer rests on it; no timer runs while nothing shows (D-33).
struct UndoToastView: View {
    private struct TimerKey: Equatable {
        let id: UUID?
        let isHovering: Bool
    }

    @State private var isHovering = false

    let undo: LayoutUndo
    let place: LayoutUndo.Place

    var body: some View {
        if let content = undo.toast, content.place == place {
            toast(for: content)
                .onHover { isHovering = $0 }
                .task(id: TimerKey(id: content.id, isHovering: isHovering)) {
                    guard !isHovering else {
                        return
                    }
                    do {
                        try await Task.sleep(for: HolzBarTheme.UndoToast.duration)
                    } catch {
                        return
                    }
                    undo.dismissToast(id: content.id)
                }
        }
    }

    @ViewBuilder
    private func toast(for content: LayoutUndo.ToastContent) -> some View {
        if content.isFailure {
            Toast(Text(verbatim: content.sentence), systemImage: "exclamationmark.triangle")
        } else {
            Toast(Text(verbatim: content.sentence), actionTitle: "Undo") {
                undo.undo()
            }
        }
    }
}

/// The target of one change's registration on the window's undo manager.
private final class UndoToken {
    weak var owner: LayoutUndo?
    let changeID: UUID

    init(owner: LayoutUndo, changeID: UUID) {
        self.owner = owner
        self.changeID = changeID
    }
}
