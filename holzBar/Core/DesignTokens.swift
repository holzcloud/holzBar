//
//  DesignTokens.swift
//  holzBar
//

import Foundation

/// The values of holzBar's design system: colours, radii, spacing and type sizes.
///
/// The values live here, apart from SwiftUI, so that a test can check them: every text
/// colour must keep its contrast over the ground it is drawn on. The views read them
/// through `HolzBarTheme`; no view uses a raw colour, radius or spacing of its own.
nonisolated enum DesignTokens {
    /// A colour in the sRGB colour space with components from 0 to 1.
    nonisolated struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Creates a colour from a value written as 0xRRGGBB.
        init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }

        static let white = RGB(hex: 0xFFFFFF)
        static let black = RGB(hex: 0x000000)

        /// The colour that results from drawing this colour with the given opacity over a
        /// background.
        func blended(over background: RGB, alpha: Double) -> RGB {
            RGB(
                red: red * alpha + background.red * (1 - alpha),
                green: green * alpha + background.green * (1 - alpha),
                blue: blue * alpha + background.blue * (1 - alpha)
            )
        }

        /// The relative luminance as WCAG 2.2 defines it.
        var relativeLuminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// A colour with an opacity, such as white at 70 % for secondary text.
    nonisolated struct Tint: Equatable, Sendable {
        let color: RGB
        let alpha: Double

        /// The colour as it appears over a background.
        func over(_ background: RGB) -> RGB {
            color.blended(over: background, alpha: alpha)
        }
    }

    /// The contrast ratio of two colours, from 1 to 21, as WCAG 2.2 defines it.
    static func contrastRatio(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(first.relativeLuminance, second.relativeLuminance)
        let darker = min(first.relativeLuminance, second.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: Colours

    /// The colours of the dark appearance, which is designed first.
    nonisolated enum Dark {
        static let ground = RGB(hex: 0x0A1426)
        static let groundBottom = RGB(hex: 0x070D1A)
        static let groundElevated = RGB(hex: 0x101C33)
        static let stroke = Tint(color: .white, alpha: 0.10)
        static let text = RGB.white
        static let textSecondary = Tint(color: .white, alpha: 0.70)
        static let textTertiary = Tint(color: .white, alpha: 0.50)
        static let accent = RGB(hex: 0x5EC0F2)
        static let success = RGB(hex: 0x4ADE80)
        static let warning = RGB(hex: 0xFBBF24)
        static let danger = RGB(hex: 0xF87171)
        static let permission = RGB(hex: 0xA78BFA)
        static let wood = RGB(hex: 0xC98B4F)
    }

    /// The colours of the light appearance.
    nonisolated enum Light {
        static let ground = RGB(hex: 0xF3F7FB)
        /// The bottom of the window ground's vertical gradient.
        static let groundBottom = RGB(hex: 0xEAF1F8)
        static let groundElevated = RGB(hex: 0xFFFFFF)
        static let stroke = Tint(color: .black, alpha: 0.08)
        static let text = RGB(hex: 0x0B1220)
        static let textSecondary = Tint(color: .black, alpha: 0.62)
        static let textTertiary = Tint(color: .black, alpha: 0.58)
        static let accent = RGB(hex: 0x1A6FA2)
        static let success = RGB(hex: 0x15803D)
        static let warning = RGB(hex: 0x92400E)
        static let danger = RGB(hex: 0xDC2626)
        static let permission = RGB(hex: 0x6D28D9)
        static let wood = RGB(hex: 0xA66F3A)
    }

    /// The values that replace their counterparts in `Dark` and `Light` while Increase
    /// Contrast is on: a stronger border and stronger secondary and tertiary text.
    nonisolated enum IncreasedContrast {
        nonisolated enum Dark {
            static let stroke = Tint(color: .white, alpha: 0.50)
            static let textSecondary = Tint(color: .white, alpha: 0.85)
            static let textTertiary = Tint(color: .white, alpha: 0.75)
        }

        nonisolated enum Light {
            static let stroke = Tint(color: .black, alpha: 0.50)
            static let textSecondary = Tint(color: .black, alpha: 0.80)
            static let textTertiary = Tint(color: .black, alpha: 0.75)
        }
    }

    /// The opacity of the Preview badge's tint behind its text.
    static let badgeFillAlpha: Double = 0.15

    /// The Notch hub, which is always dark: its ground, the parts its modules share and the
    /// strength of their small texts. The sizes and alphas are the design's numbers for the hub
    /// and its widget card; the island's own shape, rows and motion are `Island`.
    nonisolated enum Hub {
        /// The ground: pure black, one object with the hardware notch.
        static let top = RGB.black
        /// The height of a status pill beside the notch.
        static let pillHeight: Double = 24
        /// The space between the parts of the right group: the pill and its count.
        static let pillSpacing = Spacing.xs
        /// The fill of a status pill: white at 9 percent.
        static let pillFillAlpha: Double = 0.09
        /// The fill of a quiet tile on the hub's ground, such as the missing artwork: white at 8 percent.
        static let idleTabFillAlpha: Double = 0.08
        /// The colour of a module without one of its own: white at 70 percent.
        static let neutralAlpha: Double = 0.7
        /// The type size of a status pill, and the size of a module's own symbols.
        static let pillTextSize: Double = 11
        static let compactSymbolSize: Double = 16
        /// The widget card: radius, padding, the gap between cards and the columns of a row.
        static let tileRadius: Double = 14
        static let tilePadding: Double = 10
        static let tileGap: Double = 6
        static let columns = 4
        /// The small texts of a widget card: the name and the quiet line, normally and under
        /// Increase Contrast, which strengthens them.
        static let tileLabelAlpha: Double = 0.45
        static let tileDetailAlpha: Double = 0.40
        static let tileLabelAlphaIncreased: Double = 0.70
        static let tileDetailAlphaIncreased: Double = 0.70
        /// The fill of a widget card, normally and under Reduce Transparency.
        static let tileFillAlpha: Double = 0.045
        static let tileFillAlphaOpaque: Double = 0.10
        /// The File drop tab's file tile: its size, the type icon, the remove button's circle and
        /// the border (white at 6 percent). A missing file is drawn at half strength.
        static let fileTileWidth: Double = 72
        static let fileTileHeight: Double = 84
        static let fileIconSize: Double = 40
        static let fileRemoveSize: Double = 18
        static let fileTileBorderAlpha: Double = 0.06
        static let fileMissingAlpha: Double = 0.5
        /// The outline of the File drop tab while a file is dragged over it: its width, the
        /// lengths of dash and gap, and the words in it (12 pt, white at 85 percent).
        static let fileDropOutlineWidth: Double = 1.5
        static let fileDropOutlineDash: [Double] = [6, 4]
        static let fileDropOutlineAlpha: Double = 0.8
        static let fileDropLabelSize: Double = 12
        static let fileDropLabelAlpha: Double = 0.85
        /// The black behind those words, so they read over the tiles.
        static let fileDropScrimAlpha: Double = 0.6
    }

    /// The Notch hub's island (concept section 10b): the hub is the notch itself, growing, one
    /// pure black shape. Every number of the shape, its rows, its motion and its staging is here
    /// and pinned by a test; the views read them through `HolzBarTheme.Island` and
    /// `HolzBarTheme.Motion`, the geometry (`NotchHubGeometry`) reads them from here.
    nonisolated enum Island {
        /// The island's colour: pure black, so the shape and the camera housing are one object.
        /// No glass, no gradient, no stroke; it stays black in light mode.
        static let surface = RGB.black

        // MARK: Shape

        /// The concave top corners and the rounded bottom corners of the open island.
        static let openTopRadius: Double = 14
        static let openBottomRadius: Double = 40
        /// The corners of the live state, the notch widened at menu bar height.
        static let liveTopRadius: Double = 6
        static let liveBottomRadius: Double = 16
        /// The corners of the closed shape, the notch's own rectangle, where every animation
        /// starts and ends.
        static let notchTopRadius: Double = 6
        static let notchBottomRadius: Double = 10

        // MARK: Size

        /// The width of the open island, and the most it grows to when the module row needs room.
        static let baseWidth: Double = 560
        static let maximumWidth: Double = 640
        /// The inner padding of the black body, on each side.
        static let sidePadding: Double = 16

        // MARK: Rows

        /// The space between the top row and the context line's row, and the row's height.
        static let contextGap: Double = 8
        static let contextRowHeight: Double = 22
        /// The context line: white at 55 percent, with a 13 point symbol.
        static let contextTextAlpha: Double = 0.55
        static let contextSymbolSize: Double = 13
        /// The settings gear at the right end of the context line's row: its circle, its symbol
        /// (13 points, white at 60 percent) and its fill (white at 9 percent).
        static let gearSize: Double = 24
        static let gearSymbolSize: Double = 13
        static let gearFillAlpha: Double = 0.09
        static let gearSymbolAlpha: Double = 0.6

        // MARK: Content

        /// The content area's height for a module, and for an Overview of rows of cards: a row
        /// of cards is 92 points high with 6 points between rows, and the area never exceeds 190.
        static let contentHeight: Double = 110
        static let overviewRowHeight: Double = 92
        static let overviewRowGap: Double = 6
        static let maximumContentHeight: Double = 190

        // MARK: Module row

        /// The space above the module row and below it, up to the island's bottom edge.
        static let rowGap: Double = 12
        static let rowBottom: Double = 12
        /// The sizes the buttons of the module row step down through, and the space between them.
        static let buttonSizes: [Double] = [30, 26]
        static let buttonGap: Double = 6
        /// A module's symbol in its button, and the idle button's symbol and fill alphas.
        static let buttonSymbolSize: Double = 16
        static let buttonIdleSymbolAlpha: Double = 0.6
        static let buttonIdleFillAlpha: Double = 0.07

        // MARK: Live state

        /// How far the live state reaches beyond the notch, on each side, and the sizes of its
        /// symbol and its value.
        static let liveSideWidth: Double = 90
        static let liveSymbolSize: Double = 16
        static let liveValueSize: Double = 12
        /// The live state grows only over the free menu bar beside the notch (concept section
        /// 10b, 2026-11-14): the air kept to the nearest menu bar content, and the narrowest
        /// black part on one side that still shows anything (the 8 pt clearance to the notch plus
        /// 28 pt for the symbol or a short value). A side with less does not widen.
        static let liveContentGap: Double = 4
        static let liveMinimumSideWidth: Double = 36

        // MARK: Edge and margin

        /// The outline Increase Contrast adds to the lower edge only: white at 30 percent, 1 point.
        static let edgeAlpha: Double = 0.30
        static let edgeWidth: Double = 1
        /// The transparent margin of the panel on the sides and the bottom while the shape
        /// animates, so that an overshoot is never clipped.
        static let transitionMargin: Double = 12

        // MARK: Motion

        /// Opening: the width and the height each have their own spring, so the island widens a
        /// little before it deepens and overshoots slightly. The numbers are a spring's response
        /// (seconds) and damping fraction.
        static let openWidthResponse: Double = 0.42
        static let openWidthDamping: Double = 0.72
        static let openHeightResponse: Double = 0.48
        static let openHeightDamping: Double = 0.74
        /// Closing: the shape returns into the notch without overshoot.
        static let closeResponse: Double = 0.34
        static let closeDamping: Double = 0.9
        /// The content appears this long after the shape starts to grow, from a blur and a
        /// smaller scale, with a curve that takes this long; it leaves faster.
        static let contentDelay: Double = 0.09
        static let contentInDuration: Double = 0.3
        static let contentOutDuration: Double = 0.12
        static let contentBlur: Double = 10
        static let contentScale: Double = 0.94
        /// The control points of the content's curve (a cubic bezier).
        static let contentCurve: [Double] = [0.2, 0.8, 0.2, 1]
        /// Switching modules inside the hub: the content cross-fades while it rises this far.
        static let switchDuration: Double = 0.22
        static let switchRise: Double = 4
    }

    /// The gradient of fills that carry white text, the same in both appearances.
    nonisolated enum Fill {
        static let start = RGB(hex: 0x1C78AE)
        static let end = RGB(hex: 0x165F8F)
        static let label = RGB.white
    }

    /// The gradient of decorations without text, such as the glow of a progress bar.
    nonisolated enum Glow {
        static let start = RGB(hex: 0x1C78AE)
        static let end = RGB(hex: 0x5EC0F2)
    }

    // MARK: Shapes and spacing

    /// Corner radii in points. A shape inside another shape uses the outer radius minus
    /// the padding between them.
    nonisolated enum Radius {
        static let keyCap: Double = 6
        static let control: Double = 8
        /// The radius of a settings group's list (concept 9a).
        static let list: Double = 10
        static let card: Double = 16
        static let panel: Double = 22
        static let hub: Double = 28
    }

    /// The spacing scale in points.
    nonisolated enum Spacing {
        static let scale: [Double] = [4, 8, 12, 16, 20, 24, 32, 48]
        static let hairline: Double = 1
        /// The outline of the Shelf while a dragged menu bar item is over it.
        static let dropOutline: Double = 2
        static let xxs: Double = 4
        static let xs: Double = 8
        static let sm: Double = 12
        static let md: Double = 16
        static let lg: Double = 20
        static let xl: Double = 24
        static let xxl: Double = 32
        static let huge: Double = 48
    }

    /// The shadow of the floating bar (the holzBar Shelf, detached): black at 30 %, a blur of
    /// 20 points (SwiftUI's radius is half of it) and a drop of 4. It is tighter than the
    /// popover and hub shadow because a bar is small and close to the bar above it. The panel's
    /// transparent insets hold it.
    nonisolated enum Shadow {
        static let barOpacity: Double = 0.30
        static let barRadius: Double = 10
        static let barOffsetY: Double = 4
    }

    // MARK: Type

    /// The type sizes in points. The first seven are the main scale of the design; the others
    /// exist because screens built earlier use them, and new screens use the main seven.
    nonisolated enum TypeSize {
        static let title: Double = 22
        static let headline: Double = 15
        static let body: Double = 13
        static let callout: Double = 12
        static let caption: Double = 11
        static let searchField: Double = 21
        static let mono: Double = 12
        /// Badges.
        static let micro: Double = 10
        /// The About pane's lines.
        static let lead: Double = 14
        /// The version line of the About pane; the size of `headline`, in regular weight.
        static let subtitle: Double = 15
        /// The title of the Permissions window.
        static let titleLarge: Double = 40
        /// The title of the About pane.
        static let display: Double = 64
        /// Acknowledgement texts and other small monospaced text.
        static let monoMicro: Double = 10
    }

    /// Spacing that the form components keep from the design of Ice and that is not on the
    /// scale. Each is named, so that no raw number is left in the components, and pinned by a
    /// test, so that it stays what it was.
    nonisolated enum Layout {
        /// The space between the rows of a form.
        static let formRowSpacing: Double = 10
        /// The space between the rows of a section on macOS 26 and later.
        static let sectionRowSpacing: Double = 11
        /// The space between the rows of a section before macOS 26.
        static let sectionRowSpacingLegacy: Double = 10
        /// The gap between a header or footer and the card it belongs to.
        static let headerGap: Double = 2
    }

    /// The smallest size of anything the pointer or a finger must hit, in points.
    static let minimumTargetSize: Double = 24

    /// The sizes of a picture card (a small picture with a name under it) and of the widest
    /// picture drawn on one, so a row of cards keeps its cards from ever being narrower than
    /// their pictures.
    nonisolated enum PictureCard {
        /// The space between the card's edge and its picture's well.
        static let padding = Spacing.xs
        /// The width of the animation picture's strip: four items with a gap between them and
        /// room on both sides. It is the widest picture of a card.
        static let animationStripWidth = Spacing.sm * 2 + Spacing.sm * 4 + Spacing.xs * 3
        /// The narrowest a card may be: its widest picture and the padding on both sides.
        static let minimumWidth = animationStripWidth + padding * 2
        /// The space between the cards of a row.
        static let gap = Spacing.sm
    }

    /// The measures of the settings kit (concept 9a, decisions D-14 to D-26): every number of a
    /// group, row, variant, state line, disclosure, module row, info button and picture card row.
    /// The kit's views read them through `HolzBarTheme.SettingsKit`; a test pins each one.
    nonisolated enum SettingsKit {

        // Rows (D-16 to D-18)
        /// The minimum height of a settings row.
        static let rowMinHeight: Double = 30
        /// The vertical padding inside a row.
        static let rowPaddingVertical: Double = 3
        /// The horizontal padding inside a row.
        static let rowPaddingHorizontal: Double = 12
        /// The gap between a row's label and its control.
        static let labelControlGap: Double = 16
        /// The gap between a label and its info button or Preview badge.
        static let accessoryGap: Double = 6
        /// How far a sub row is indented beyond a row's horizontal padding.
        static let subRowInset: Double = 18
        /// The opacity of a row whose switch above it is off.
        static let dependentOpacity: Double = 0.42
        /// The hit height of a switch: the smallest target (D-23).
        static let switchMinHeight: Double = minimumTargetSize

        // Groups (D-16)
        /// The inset of a group header.
        static let groupHeaderInset: Double = 4
        /// The gap between a group header and its list.
        static let groupHeaderGap: Double = 6
        /// The gap between two groups.
        static let groupGap: Double = 14
        /// The gap between a list and its footnote.
        static let footnoteGap: Double = 6
        /// The inset of a footnote.
        static let footnoteInset: Double = 4

        // Row variants (D-18)
        /// The widest a pop-up button gets.
        static let popUpMaxWidth: Double = 260
        /// The width of a slider's track.
        static let sliderTrackWidth: Double = 120
        /// The gap between a slider and its value.
        static let sliderValueGap: Double = 10
        /// The narrowest the value beside a slider gets.
        static let sliderValueMinWidth: Double = 34
        /// The gap between a stepper and its value.
        static let stepperValueGap: Double = 6
        /// The narrowest a text field in a row gets.
        static let textFieldMinWidth: Double = 150
        /// The width of a color well.
        static let colorWellWidth: Double = 40
        /// The height of a color well.
        static let colorWellHeight: Double = 20
        /// The corner radius of a color well.
        static let colorWellRadius: Double = 6
        /// The width of a gradient strip.
        static let gradientStripWidth: Double = 96
        /// The width of a hotkey recorder.
        static let hotkeyRecorderWidth: Double = 132
        /// The height of a hotkey recorder; a row is at least as high.
        static let hotkeyRecorderHeight: Double = 24

        // State and note lines, disclosure (D-19, D-20)
        /// The gap inside a state line.
        static let stateLineGap: Double = 8
        /// The vertical padding of a note line.
        static let noteLinePaddingVertical: Double = 8
        /// The horizontal padding of a note line.
        static let noteLinePaddingHorizontal: Double = 12
        /// The size of a disclosure chevron.
        static let disclosureChevronSize: Double = 10

        // Module row (D-21)
        /// The minimum height of a module row.
        static let moduleRowMinHeight: Double = 38
        /// The gap inside a module row.
        static let moduleRowGap: Double = 10
        /// The size of a module's symbol tile.
        static let moduleTileSize: Double = 24
        /// The corner radius of a module's symbol tile.
        static let moduleTileRadius: Double = 7
        /// The size of the symbol inside the tile.
        static let moduleSymbolSize: Double = 14
        /// The size of the chevron button of a module row.
        static let moduleChevronButtonSize: Double = 22
        /// The size of the chevron.
        static let moduleChevronSize: Double = 10
        /// The inset of a module's open area.
        static let openAreaInset: Double = 46
        /// The accent fill of a tile in light appearance.
        static let accentFillLight: Double = 0.12
        /// The accent fill of a tile in dark appearance.
        static let accentFillDark: Double = 0.16
        /// The fill of an open area in light appearance.
        static let openAreaFillLight: Double = 0.07
        /// The fill of an open area in dark appearance.
        static let openAreaFillDark: Double = 0.08

        // Info button and texts (D-22)
        /// The size of the info button's circle.
        static let infoButtonSize: Double = 14
        /// The line width of the info button's circle.
        static let infoButtonLineWidth: Double = 1.3
        /// The hit area of the info button (at least 28, concept 11).
        static let infoButtonHitArea: Double = 28
        /// The widest an info popover gets.
        static let infoPopoverMaxWidth: Double = 290
        /// The vertical padding of an info popover.
        static let infoPopoverPaddingVertical: Double = 10
        /// The horizontal padding of an info popover.
        static let infoPopoverPaddingHorizontal: Double = 12
        /// The longest an info text may be, in characters.
        static let infoTextMaxCharacters: Double = 200
        /// The longest small text beside a label, in words.
        static let smallTextMaxWords: Double = 3

        // Picture card row (D-24)
        /// The gap between picture cards.
        static let pictureCardGap: Double = 10
        /// The vertical padding of a picture card row.
        static let pictureCardRowPaddingVertical: Double = 10
        /// The horizontal padding of a picture card row.
        static let pictureCardRowPaddingHorizontal: Double = 12
        /// The stroke of a selected picture card.
        static let pictureCardStrokeWidth: Double = 1.5
        /// The padding inside a picture card.
        static let pictureCardPadding: Double = 8
        /// The height of a picture's well.
        static let pictureWellHeight: Double = 42
        /// The corner radius of a picture's well.
        static let pictureWellRadius: Double = 6
        /// The width of a compact picture card.
        static let pictureCardCompactWidth: Double = 78
        /// How many cards a row holds before they turn compact.
        static let pictureCardsBeforeCompact: Double = 4

        // Pane margins (D-26)
        /// The horizontal margin of a pane.
        static let paneMarginHorizontal: Double = 20
        /// The top margin of a pane.
        static let paneMarginTop: Double = 4
        /// The bottom margin of a pane.
        static let paneMarginBottom: Double = 22
    }

    /// The onboarding window (D-22, D-36).
    nonisolated enum Onboarding {
        /// The width of the window's content.
        static let width: Double = 440
        /// The height of the picture well above each step's title.
        static let pictureHeight: Double = 44
        /// The size of a page dot.
        static let dotSize: Double = 6
    }

    /// The list view of Layout (mock-up 01, D-08).
    nonisolated enum LayoutList {
        /// The width of the App column (mock-up 01).
        static let appColumnWidth: Double = 150
        /// The width of the Section column (mock-up 01).
        static let sectionColumnWidth: Double = 150
        /// The size of an item's picture in a row.
        static let iconSize: Double = 20
        /// The least width of the filter field in Layout's top row.
        static let filterFieldMinWidth: Double = 112
        /// The opacity of a tile in the bars that the filter leaves out (D-09).
        static let filteredOutOpacity: Double = 0.25
        /// The width of the ring around the items of the app under the pointer (macOS 27, D-11).
        static let siblingRingWidth: Double = 2
    }

    /// The undo toast: a glass capsule with one sentence and an Undo button (concept 9a, D-13).
    nonisolated enum UndoToast {
        /// The vertical padding inside the capsule (D-13).
        static let paddingVertical: Double = 7
        /// The horizontal padding inside the capsule (D-13).
        static let paddingHorizontal: Double = 12
        /// The gap between the symbol, the sentence and the Undo button (D-13).
        static let gap: Double = 10
        /// How long the toast with an Undo button stays, in seconds (D-03).
        static let visibleSeconds: Double = 5
        /// How long a plain toast without an action stays, in seconds (concept 9, row `Toast`).
        static let plainVisibleSeconds: Double = 3
        /// The gap between the menu bar and the toast of a change made there (D-14).
        static let menuBarGap: Double = 8
        /// The least distance between that toast and the screen's edge.
        static let screenMargin: Double = 8
    }

    /// The sidebar and the window of the Settings window (concept 10, D-08, D-26).
    nonisolated enum SettingsSidebar {
        /// The measures that follow the system's sidebar icon size.
        nonisolated struct Metrics: Equatable, Sendable {
            let width: Double
            let textSize: Double
            let symbolSize: Double
            let rowHeight: Double
        }

        /// The small system sidebar size (chosen by the planner, adjusted after the Mac test).
        static let small = Metrics(width: 200, textSize: 13, symbolSize: 17, rowHeight: 28)
        /// The medium system sidebar size (D-08).
        static let medium = Metrics(width: 210, textSize: 14, symbolSize: 22, rowHeight: 32)
        /// The large system sidebar size (chosen by the planner, adjusted after the Mac test).
        static let large = Metrics(width: 230, textSize: 16, symbolSize: 25, rowHeight: 36)
        /// The corner radius of a sidebar row: the control radius.
        static let rowRadius: Double = Radius.control
        /// The horizontal padding of a sidebar row.
        static let rowPadding: Double = 10
        /// The gap between a row's symbol and its text.
        static let symbolTextGap: Double = 10
        /// The gap between sidebar rows.
        static let rowGap: Double = 2
        /// The gap between the sidebar's groups.
        static let moduleGap: Double = 10
        /// The height of the search field.
        static let searchFieldHeight: Double = 28
        /// The size of the search field's magnifier.
        static let searchMagnifierSize: Double = 13
        /// The gap under the search field.
        static let searchFieldBottomGap: Double = 8
        /// The height of the title bar (D-67).
        static let titleBarHeight: Double = 44
        /// The narrowest the Settings window gets.
        static let minimumWindowWidth: Double = 760
        /// The lowest the Settings window gets.
        static let minimumWindowHeight: Double = 540
    }

    /// The minimum contrast ratios the design asks for.
    nonisolated enum RequiredContrast {
        /// Body text and anything smaller than 18 pt.
        static let text: Double = 4.5
        /// Large text and the borders of controls.
        static let component: Double = 3.0
    }
}
