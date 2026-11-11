//
//  SettingsPictureRow.swift
//  holzBar
//

import SwiftUI

/// A row without a label that shows a picture across the row, under a switch whose effect the
/// picture shows. The picture repeats what the switch and the rows around it say, so VoiceOver
/// skips it. It takes the same chrome as every kit row, so its hairline is part of the layout.
struct SettingsPictureRow<Picture: View>: View {
    private let picture: Picture

    init(@ViewBuilder picture: () -> Picture) {
        self.picture = picture()
    }

    var body: some View {
        picture
            .frame(maxWidth: .infinity)
            .settingsRowChrome(
                verticalPadding: HolzBarTheme.SettingsKit.pictureCardRowPaddingVertical,
                trailingPadding: HolzBarTheme.SettingsKit.pictureCardRowPaddingHorizontal
            )
            .accessibilityHidden(true)
    }
}
