//
//  TransparencyTreatment.swift
//  holzBar
//

import Foundation

/// The system's two display options that ask apps to stop using semi-transparent
/// backgrounds and to draw bolder edges (System Settings, Accessibility, Display).
nonisolated struct TransparencyOptions: Equatable, Sendable {
    /// Whether Reduce Transparency is on: backgrounds should be opaque.
    var reduceTransparency = false

    /// Whether Increase Contrast is on: a less subtle palette and bolder lines.
    var increaseContrast = false

    /// Whether either option asks for opaque backgrounds.
    var prefersOpaque: Bool {
        reduceTransparency || increaseContrast
    }
}

/// How holzBar draws a surface of its own (the System Glass tint of the menu bar, the
/// holzBar Shelf) under ``TransparencyOptions``.
///
/// With either option on, the surface is an opaque fill, and it gets a visible border unless
/// the user has configured one. With both off, or for a menu bar tint that is not System
/// Glass (the user's own colours), nothing changes.
nonisolated struct TransparencyTreatment: Equatable, Sendable {
    /// How the surface is filled.
    enum Fill: Equatable, Sendable {
        /// As designed: glass, or the tint the user chose.
        case asDesigned
        /// An opaque fill.
        case opaque
    }

    /// How the surface's border is drawn.
    enum Border: Equatable, Sendable {
        /// As the user configured it, or none.
        case asConfigured
        /// A visible line of ``visibleBorderWidth`` at ``borderOpacity``.
        case visible
    }

    /// The width of a visible border, in points.
    static let visibleBorderWidth = 1.0

    /// The opacity of a visible border while Increase Contrast is on (a bolder line).
    static let increasedContrastBorderOpacity = 0.9

    /// The opacity of a visible border while only Reduce Transparency is on.
    static let reducedTransparencyBorderOpacity = 0.6

    /// Nothing changes.
    static let unchanged = TransparencyTreatment(fill: .asDesigned, border: .asConfigured, borderOpacity: 0)

    /// How the surface is filled.
    var fill: Fill

    /// How the surface's border is drawn.
    var border: Border

    /// The opacity of the border when it is ``Border/visible``, otherwise 0.
    var borderOpacity: Double

    /// The treatment of the menu bar overlay.
    ///
    /// - Parameters:
    ///   - isGlass: Whether the tint in use is System Glass. The solid, gradient and Follow
    ///     Wallpaper tints are the user's own colours and are never changed.
    ///   - options: The system's options.
    ///   - hasConfiguredBorder: Whether the user has configured a border.
    static func menuBar(isGlass: Bool, options: TransparencyOptions, hasConfiguredBorder: Bool) -> TransparencyTreatment {
        guard isGlass else {
            return .unchanged
        }
        return treatment(options: options, hasConfiguredBorder: hasConfiguredBorder)
    }

    /// The treatment of the holzBar Shelf.
    ///
    /// - Parameters:
    ///   - options: The system's options.
    ///   - hasConfiguredBorder: Whether the user has configured a border.
    static func shelf(options: TransparencyOptions, hasConfiguredBorder: Bool) -> TransparencyTreatment {
        treatment(options: options, hasConfiguredBorder: hasConfiguredBorder)
    }

    private static func treatment(options: TransparencyOptions, hasConfiguredBorder: Bool) -> TransparencyTreatment {
        guard options.prefersOpaque else {
            return .unchanged
        }
        // The user's own border wins: it is their choice, and a second line would double it.
        guard !hasConfiguredBorder else {
            return TransparencyTreatment(fill: .opaque, border: .asConfigured, borderOpacity: 0)
        }
        let opacity = options.increaseContrast ? increasedContrastBorderOpacity : reducedTransparencyBorderOpacity
        return TransparencyTreatment(fill: .opaque, border: .visible, borderOpacity: opacity)
    }
}
