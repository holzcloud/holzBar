//
//  HolzBarGlass.swift
//  holzBar
//

import SwiftUI

/// The kinds of glass holzBar draws.
enum HolzBarGlassStyle: Sendable {
    /// The standard glass of bars, panels and popovers.
    case regular
    /// More transparent glass, only over rich content such as artwork.
    case clear
    /// Glass tinted with the accent, for the one primary action of a surface.
    case prominent
}

extension View {
    /// Draws the view on Liquid Glass, or on its replacement where there is none.
    ///
    /// - macOS 26 and later: Apple's Liquid Glass.
    /// - Earlier macOS: a system material with the same shape.
    /// - Reduce Transparency: an opaque elevated ground with a hairline border.
    ///
    /// Glass is for the layer that floats above content (bars, panels, popovers), never for
    /// the content itself and never on top of other glass.
    ///
    /// - Parameters:
    ///   - style: The kind of glass.
    ///   - shape: The shape the glass takes.
    ///   - interactive: Whether the glass reacts to the pointer, for tappable surfaces.
    func holzBarGlass<S: Shape>(
        _ style: HolzBarGlassStyle = .regular,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        modifier(HolzBarGlassModifier(style: style, shape: shape, interactive: interactive))
    }
}

private struct HolzBarGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let style: HolzBarGlassStyle
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(HolzBarTheme.Palette.groundElevated, in: shape)
                .overlay {
                    shape.stroke(
                        HolzBarTheme.Palette.stroke,
                        lineWidth: HolzBarTheme.Spacing.hairline
                    )
                }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(
                        HolzBarTheme.Palette.stroke,
                        lineWidth: HolzBarTheme.Spacing.hairline
                    )
                }
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = switch style {
        case .regular: .regular
        case .clear: .clear
        case .prominent: .regular.tint(HolzBarTheme.Palette.accent)
        }
        return interactive ? base.interactive() : base
    }
}
