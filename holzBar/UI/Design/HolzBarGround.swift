//
//  HolzBarGround.swift
//  holzBar
//

import SwiftUI

/// The ground of a window: the calm ground colour with two soft glows, the logo blue at the
/// top right and the wood of the logo at the bottom left, so the glass above it has
/// something to refract. The glass is the only layer above it.
struct HolzBarGround: View {
    var body: some View {
        ZStack {
            HolzBarTheme.Palette.ground
            RadialGradient(
                colors: [HolzBarTheme.Palette.accent.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [HolzBarTheme.Palette.wood.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

#Preview("HolzBarGround") {
    HolzBarGround()
        .frame(width: 600, height: 400)
}
