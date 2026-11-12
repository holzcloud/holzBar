//
//  MenuBarShapePicker.swift
//  holzBar
//

import SwiftUI

/// The rows of the shape kind and its end caps, as direct children of the "Menu bar shape" group
/// (no group and no stack of its own). The end-cap rows are built only while a shape is drawn
/// (D-71): Single has one pair, Paired and Sections have a pair for each half.
struct MenuBarShapePicker: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        shapeKindRow
        endCapRows
    }

    @ViewBuilder
    private var shapeKindRow: some View {
        // A stored Sections shows as Paired where macOS cannot draw it, and stays stored until
        // another kind is picked.
        let selection = Binding(
            get: { configuration.shapeKind.drawnKind },
            set: { configuration.shapeKind = $0 }
        )
        SettingsPictureCardRow(
            .appearanceShapeKind,
            selection: selection,
            values: MenuBarShapeKind.allCases.filter(\.isAvailable),
            name: { Text($0.localized) },
            picture: { MenuBarShapePicture(kind: $0) }
        )
    }

    @ViewBuilder
    private var endCapRows: some View {
        switch configuration.shapeKind.drawnKind {
        case .noShape:
            EmptyView()
        case .full:
            SettingsSegmentedRow(.appearanceLeadingEnd, selection: $configuration.fullShapeInfo.leadingEndCap) {
                endCapOptions
            }
            .settingsSubRow()
            SettingsSegmentedRow(.appearanceTrailingEnd, selection: $configuration.fullShapeInfo.trailingEndCap) {
                endCapOptions
            }
            .settingsSubRow()
        case .split, .sections:
            // Sections shares the end caps of Paired. The right half repeats the labels, so its
            // rows have no entry of their own.
            SettingsSegmentedRow(.appearanceLeadingEnd, selection: $configuration.splitShapeInfo.leading.leadingEndCap) {
                endCapOptions
            }
            .settingsSubRow()
            SettingsSegmentedRow(.appearanceTrailingEnd, selection: $configuration.splitShapeInfo.leading.trailingEndCap) {
                endCapOptions
            }
            .settingsSubRow()
            SettingsSegmentedRow(
                Text("Leading end"),
                selection: $configuration.splitShapeInfo.trailing.leadingEndCap,
                small: Text("right half")
            ) {
                endCapOptions
            }
            .settingsSubRow()
            SettingsSegmentedRow(
                Text("Trailing end"),
                selection: $configuration.splitShapeInfo.trailing.trailingEndCap,
                small: Text("right half")
            ) {
                endCapOptions
            }
            .settingsSubRow()
        }
    }

    /// Round first on both sides.
    @ViewBuilder
    private var endCapOptions: some View {
        Text("Round").tag(MenuBarEndCap.round)
        Text("Square").tag(MenuBarEndCap.square)
    }
}
