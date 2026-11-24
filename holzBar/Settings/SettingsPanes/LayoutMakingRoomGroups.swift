//
//  LayoutMakingRoomGroups.swift
//  holzBar
//

import SwiftUI

/// The group Making room of the Layout pane (Phase 97, D-10, D-12, concept M7): what holzBar does
/// when macOS 27 folds items away because the bar is full, and whether it asks where a new app
/// goes. The two rows are independent and neither dims the other; both apply at once.
///
/// The group exists only on macOS 27, where the Layout pane has the fit model.
@available(macOS 27.0, *)
struct MakingRoomGroup: View {
    @Bindable var advanced: AdvancedSettings

    var body: some View {
        SettingsGroup(SettingsCatalog.LayoutPane.makingRoom) {
            SettingsPickerRow(.layoutMakeRoomMode, selection: modeBinding, badge: .preview) {
                Text(MakeRoomMode.off.localized).tag(MakeRoomMode.off)
                Text(MakeRoomMode.ask.localized).tag(MakeRoomMode.ask)
            }
            SettingsToggleRow(.layoutAsksWhereNewAppGoes, isOn: $advanced.asksWhereNewAppGoes, badge: .preview)
        }
    }

    /// The pop-up shows a stored Automatic as Ask until a later release lists it, because it
    /// behaves as Ask until then; choosing never writes Automatic.
    private var modeBinding: Binding<MakeRoomMode> {
        Binding(
            get: { advanced.makeRoomMode == .off ? .off : .ask },
            set: { advanced.makeRoomMode = $0 }
        )
    }
}
