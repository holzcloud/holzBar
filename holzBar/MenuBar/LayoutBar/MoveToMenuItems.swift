//
//  MoveToMenuItems.swift
//  holzBar
//

import SwiftUI

/// "Move to Visible", "Move to Hidden" and "Move to Always Hidden" for an item outside Settings:
/// the search panel's context menu and the Shelf tiles' VoiceOver actions (D-18). The move goes
/// on the bar at once, as a drop in the menu bar does, with the undo toast under the menu bar.
struct MoveToMenuItems: View {
    let item: MenuBarItem
    /// The section the item is in now.
    let section: MenuBarSection.Name
    let appState: AppState

    var body: some View {
        ForEach(appState.layoutEditor.availableSections.filter { $0 != section }, id: \.self) { target in
            Button(title(for: target)) {
                LayoutBarMoves.setSection(of: item, to: target, appState: appState, place: .menuBar)
            }
            .disabled(item.isControlItem || appState.layoutEditor.paneMoveRefusal(for: item) != nil)
        }
    }

    private func title(for target: MenuBarSection.Name) -> LocalizedStringKey {
        switch target {
        case .visible: "Move to Visible"
        case .hidden: "Move to Hidden"
        case .alwaysHidden: "Move to Always Hidden"
        }
    }
}
