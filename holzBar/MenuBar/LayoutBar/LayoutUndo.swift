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
        for dropped in history.push(change) {
            dropped.onDiscard?()
        }
        canUndo = !history.isEmpty
        toast = ToastContent(id: UUID(), sentence: change.sentence, isFailure: false, place: place)
        LayoutBarItemView.announce(change.sentence)
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
        let place = toast?.place ?? .settings
        toast = nil
        Task {
            let isRestored = await change.perform()
            report(isRestored: isRestored, place: place)
        }
    }

    /// Hides the toast with the given identifier, if it still shows.
    func dismissToast(id: UUID) {
        if toast?.id == id {
            toast = nil
        }
    }

    // MARK: Private

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
                await self?.restore(before) ?? true
            }
        )
    }

    /// Puts the sections of `before` back and tells whether everything is back.
    private func restore(_ before: LayoutSnapshot) async -> Bool {
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

    /// Shows a toast when an undo could not put everything back; otherwise nothing (D-17).
    private func report(isRestored: Bool, place: Place) {
        guard !isRestored else {
            return
        }
        let sentence = String(localized: "Some items could not be put back.")
        toast = ToastContent(id: UUID(), sentence: sentence, isFailure: true, place: place)
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
    private struct TimerKey: Equatable {
        let id: UUID?
        let isHovering: Bool
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let undo: LayoutUndo
    let place: LayoutUndo.Place

    private var content: LayoutUndo.ToastContent? {
        undo.toast.flatMap { $0.place == place ? $0 : nil }
    }

    func body(content view: Content) -> some View {
        view
            .overlay(alignment: .bottom) {
                if let content {
                    toast(for: content)
                        .onHover { isHovering = $0 }
                        .padding(.bottom, HolzBarTheme.Spacing.lg)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
                value: content
            )
            .task(id: TimerKey(id: content?.id, isHovering: isHovering)) {
                guard let id = content?.id, !isHovering else {
                    return
                }
                do {
                    try await Task.sleep(for: HolzBarTheme.UndoToast.duration)
                } catch {
                    return
                }
                undo.dismissToast(id: id)
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
