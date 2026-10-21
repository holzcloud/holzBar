//
//  HolzBarGround.swift
//  holzBar
//

import SwiftUI

/// The ground of a window: a calm vertical fall from the ground colour to a slightly deeper
/// one, with two soft glows, the logo blue at the top right and the wood of the logo at the
/// bottom left, so the glass above it has something to refract. The glass is the only layer
/// above it.
///
/// With Increase Contrast the ground is flat: no fall and no glow, so nothing lowers the
/// contrast of the text above it.
struct HolzBarGround: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if contrast == .increased {
                HolzBarTheme.Palette.ground
            } else {
                LinearGradient(
                    colors: [HolzBarTheme.Palette.ground, HolzBarTheme.Palette.groundBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [HolzBarTheme.Palette.accent.opacity(0.26), .clear],
                    center: UnitPoint(x: 0.85, y: -0.05),
                    startRadius: 0,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [HolzBarTheme.Palette.wood.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.3, y: 1.1),
                    startRadius: 0,
                    endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
    }
}

#Preview("HolzBarGround") {
    HolzBarGround()
        .frame(width: 600, height: 400)
}
