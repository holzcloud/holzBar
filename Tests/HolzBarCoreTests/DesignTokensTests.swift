import Testing
@testable import HolzBarCore

@Suite("DesignTokens")
struct DesignTokensTests {
    private typealias Tokens = DesignTokens

    @Test("A picture card is never narrower than its widest picture and padding, and sits on the scale")
    func pictureCardFitsItsPicture() {
        let card = Tokens.PictureCard.self
        #expect(card.animationStripWidth == 96)
        #expect(card.minimumWidth >= card.animationStripWidth + card.padding * 2)
        #expect(Tokens.Spacing.scale.contains(card.padding))
        #expect(Tokens.Spacing.scale.contains(card.gap))
        // The cards of a row are apart, so the border of a selected card never touches the next.
        #expect(card.gap > 2)
    }

    @Test("A hex value is split into its channels")
    func hexIsSplit() {
        let colour = Tokens.RGB(hex: 0x1C78AE)
        #expect(abs(colour.red - 28.0 / 255) < 1e-9)
        #expect(abs(colour.green - 120.0 / 255) < 1e-9)
        #expect(abs(colour.blue - 174.0 / 255) < 1e-9)
    }

    @Test("Black on white has a contrast of 21")
    func blackOnWhite() {
        #expect(abs(Tokens.contrastRatio(.black, .white) - 21) < 1e-9)
        #expect(abs(Tokens.contrastRatio(.white, .white) - 1) < 1e-9)
    }

    @Test("Blending white at half opacity over black gives mid grey")
    func blending() {
        let grey = Tokens.RGB.white.blended(over: .black, alpha: 0.5)
        #expect(abs(grey.red - 0.5) < 1e-9)
        #expect(abs(grey.green - 0.5) < 1e-9)
        #expect(abs(grey.blue - 0.5) < 1e-9)
    }

    @Test("Dark appearance: text keeps its contrast over every ground")
    func darkTextContrast() {
        let grounds = [Tokens.Dark.ground, Tokens.Dark.groundBottom, Tokens.Dark.groundElevated]
        for ground in grounds {
            let primary = Tokens.contrastRatio(Tokens.Dark.text, ground)
            let secondary = Tokens.contrastRatio(Tokens.Dark.textSecondary.over(ground), ground)
            let tertiary = Tokens.contrastRatio(Tokens.Dark.textTertiary.over(ground), ground)
            let accent = Tokens.contrastRatio(Tokens.Dark.accent, ground)
            #expect(primary >= 7)
            #expect(secondary >= Tokens.RequiredContrast.text)
            #expect(tertiary >= Tokens.RequiredContrast.text)
            #expect(accent >= Tokens.RequiredContrast.text)
        }
    }

    @Test("Light appearance: text keeps its contrast over every ground")
    func lightTextContrast() {
        let grounds = [Tokens.Light.ground, Tokens.Light.groundBottom, Tokens.Light.groundElevated]
        for ground in grounds {
            let primary = Tokens.contrastRatio(Tokens.Light.text, ground)
            let secondary = Tokens.contrastRatio(Tokens.Light.textSecondary.over(ground), ground)
            let tertiary = Tokens.contrastRatio(Tokens.Light.textTertiary.over(ground), ground)
            let accent = Tokens.contrastRatio(Tokens.Light.accent, ground)
            #expect(primary >= 7)
            #expect(secondary >= Tokens.RequiredContrast.text)
            #expect(tertiary >= Tokens.RequiredContrast.text)
            #expect(accent >= Tokens.RequiredContrast.text)
        }
    }

    @Test("The window ground falls: its bottom is darker than its top in both appearances")
    func groundFalls() {
        #expect(Tokens.Dark.groundBottom.relativeLuminance < Tokens.Dark.ground.relativeLuminance)
        #expect(Tokens.Light.groundBottom.relativeLuminance < Tokens.Light.ground.relativeLuminance)
    }

    @Test("State colours are readable as text and as indicators")
    func stateColours() {
        let dark: [Tokens.RGB] = [
            Tokens.Dark.success, Tokens.Dark.warning, Tokens.Dark.danger, Tokens.Dark.permission
        ]
        for colour in dark {
            #expect(Tokens.contrastRatio(colour, Tokens.Dark.groundElevated) >= Tokens.RequiredContrast.text)
        }
        let light: [Tokens.RGB] = [
            Tokens.Light.success, Tokens.Light.warning, Tokens.Light.danger, Tokens.Light.permission
        ]
        for colour in light {
            #expect(Tokens.contrastRatio(colour, Tokens.Light.groundElevated) >= Tokens.RequiredContrast.text)
        }
    }

    @Test("Increase Contrast: borders reach 3:1 over every ground")
    func increasedContrastBorders() {
        let darkGrounds = [Tokens.Dark.ground, Tokens.Dark.groundBottom, Tokens.Dark.groundElevated]
        for ground in darkGrounds {
            let stroke = Tokens.IncreasedContrast.Dark.stroke.over(ground)
            #expect(Tokens.contrastRatio(stroke, ground) >= Tokens.RequiredContrast.component)
        }
        let lightGrounds = [Tokens.Light.ground, Tokens.Light.groundBottom, Tokens.Light.groundElevated]
        for ground in lightGrounds {
            let stroke = Tokens.IncreasedContrast.Light.stroke.over(ground)
            #expect(Tokens.contrastRatio(stroke, ground) >= Tokens.RequiredContrast.component)
        }
    }

    @Test("Increase Contrast: secondary and tertiary text reach 7:1 and are stronger than without it")
    func increasedContrastText() {
        func check(ground: Tokens.RGB, normal: [Tokens.Tint], increased: [Tokens.Tint]) {
            for (normalTint, increasedTint) in zip(normal, increased) {
                let before = Tokens.contrastRatio(normalTint.over(ground), ground)
                let after = Tokens.contrastRatio(increasedTint.over(ground), ground)
                #expect(after >= 7)
                #expect(after > before)
            }
        }
        let darkGrounds = [Tokens.Dark.ground, Tokens.Dark.groundBottom, Tokens.Dark.groundElevated]
        for ground in darkGrounds {
            check(
                ground: ground,
                normal: [Tokens.Dark.textSecondary, Tokens.Dark.textTertiary],
                increased: [
                    Tokens.IncreasedContrast.Dark.textSecondary,
                    Tokens.IncreasedContrast.Dark.textTertiary
                ]
            )
        }
        let lightGrounds = [Tokens.Light.ground, Tokens.Light.groundBottom, Tokens.Light.groundElevated]
        for ground in lightGrounds {
            check(
                ground: ground,
                normal: [Tokens.Light.textSecondary, Tokens.Light.textTertiary],
                increased: [
                    Tokens.IncreasedContrast.Light.textSecondary,
                    Tokens.IncreasedContrast.Light.textTertiary
                ]
            )
        }
    }

    @Test("The Preview badge's text keeps 4.5:1 over its own tint")
    func previewBadgeContrast() {
        let darkGrounds = [Tokens.Dark.ground, Tokens.Dark.groundBottom, Tokens.Dark.groundElevated]
        for ground in darkGrounds {
            let fill = Tokens.Dark.warning.blended(over: ground, alpha: Tokens.badgeFillAlpha)
            #expect(Tokens.contrastRatio(Tokens.Dark.warning, fill) >= Tokens.RequiredContrast.text)
        }
        let lightGrounds = [Tokens.Light.ground, Tokens.Light.groundBottom, Tokens.Light.groundElevated]
        for ground in lightGrounds {
            let fill = Tokens.Light.warning.blended(over: ground, alpha: Tokens.badgeFillAlpha)
            #expect(Tokens.contrastRatio(Tokens.Light.warning, fill) >= Tokens.RequiredContrast.text)
        }
    }

    @Test("White text stays readable on the whole fill gradient")
    func fillGradientCarriesWhiteText() {
        #expect(Tokens.contrastRatio(Tokens.Fill.label, Tokens.Fill.start) >= Tokens.RequiredContrast.text)
        #expect(Tokens.contrastRatio(Tokens.Fill.label, Tokens.Fill.end) >= Tokens.RequiredContrast.text)
    }

    @Test("The spacing scale ascends and every named step is in it")
    func spacingScale() {
        let scale = Tokens.Spacing.scale
        #expect(scale == scale.sorted())
        let named = [
            Tokens.Spacing.xxs, Tokens.Spacing.xs, Tokens.Spacing.sm, Tokens.Spacing.md,
            Tokens.Spacing.lg, Tokens.Spacing.xl, Tokens.Spacing.xxl, Tokens.Spacing.huge
        ]
        #expect(named == scale)
    }

    @Test("The Shelf's drop outline is 2 points")
    func dropOutline() {
        #expect(Tokens.Spacing.dropOutline == 2)
    }

    @Test("Radii ascend from control to hub")
    func radii() {
        let radii = [
            Tokens.Radius.keyCap, Tokens.Radius.control, Tokens.Radius.list, Tokens.Radius.card,
            Tokens.Radius.panel, Tokens.Radius.hub
        ]
        #expect(radii == radii.sorted())
    }

    @Test("The list radius is 10, between control and card")
    func listRadius() {
        #expect(Tokens.Radius.list == 10)
    }

    @Test("The form layout constants keep the values the components always had")
    func layoutConstantsKeepTheirValues() {
        #expect(Tokens.Layout.formRowSpacing == 10)
        #expect(Tokens.Layout.sectionRowSpacing == 11)
        #expect(Tokens.Layout.sectionRowSpacingLegacy == 10)
        #expect(Tokens.Layout.headerGap == 2)
    }

    @Test("The form layout constants are off the spacing scale, by design")
    func layoutConstantsAreOffTheScale() {
        let constants = [
            Tokens.Layout.formRowSpacing, Tokens.Layout.sectionRowSpacing,
            Tokens.Layout.sectionRowSpacingLegacy, Tokens.Layout.headerGap
        ]
        for constant in constants {
            #expect(!Tokens.Spacing.scale.contains(constant))
        }
    }

    @Test("The type sizes equal the design's table")
    func typeSizesEqualTheTable() {
        typealias Size = Tokens.TypeSize
        #expect(Size.title == 22)
        #expect(Size.headline == 15)
        #expect(Size.body == 13)
        #expect(Size.callout == 12)
        #expect(Size.caption == 11)
        #expect(Size.searchField == 21)
        #expect(Size.mono == 12)
        #expect(Size.micro == 10)
        #expect(Size.lead == 14)
        #expect(Size.subtitle == 15)
        #expect(Size.titleLarge == 40)
        #expect(Size.display == 64)
        #expect(Size.monoMicro == 10)
    }

    @Test("The type scale is ordered from micro to display")
    func typeScaleIsOrdered() {
        typealias Size = Tokens.TypeSize
        let ascending = [
            Size.micro, Size.caption, Size.callout, Size.body, Size.lead, Size.headline,
            Size.searchField, Size.title, Size.titleLarge, Size.display
        ]
        #expect(ascending == ascending.sorted())
        #expect(Set(ascending).count == ascending.count)
    }

    @Test("Some type tokens share a size and differ only in weight or design")
    func typeTokensThatShareASize() {
        typealias Size = Tokens.TypeSize
        #expect(Size.subtitle == Size.headline)
        #expect(Size.monoMicro == Size.micro)
        #expect(Size.mono == Size.callout)
    }

    @Test("Every type size is a whole number of points between 10 and 64")
    func typeSizesAreWholeNumbers() {
        typealias Size = Tokens.TypeSize
        let all = [
            Size.title, Size.headline, Size.body, Size.callout, Size.caption, Size.searchField,
            Size.mono, Size.micro, Size.lead, Size.subtitle, Size.titleLarge, Size.display,
            Size.monoMicro
        ]
        for size in all {
            #expect(size == size.rounded())
            #expect(size >= 10)
            #expect(size <= 64)
        }
    }

    @Test("The hub's ground is pure black, the island's colour")
    func hubGround() {
        #expect(Tokens.Hub.top == .black)
        #expect(Tokens.Hub.top == Tokens.Island.surface)
    }

    @Test("The hub's small texts keep 4.5:1 under Increase Contrast, which makes them stronger")
    func hubTextContrast() {
        // Over the black ground, and over a widget card on it in its most opaque form.
        let card = Tokens.Tint(color: .white, alpha: Tokens.Hub.tileFillAlphaOpaque)
        let grounds = [Tokens.Hub.top, card.over(Tokens.Hub.top)]
        for alpha in [Tokens.Hub.tileLabelAlphaIncreased, Tokens.Hub.tileDetailAlphaIncreased] {
            let text = Tokens.Tint(color: .white, alpha: alpha)
            for ground in grounds {
                #expect(Tokens.contrastRatio(text.over(ground), ground) >= Tokens.RequiredContrast.text)
            }
        }
        #expect(Tokens.Hub.tileLabelAlphaIncreased > Tokens.Hub.tileLabelAlpha)
        #expect(Tokens.Hub.tileDetailAlphaIncreased > Tokens.Hub.tileDetailAlpha)
        #expect(Tokens.Hub.tileLabelAlpha == 0.45)
        #expect(Tokens.Hub.tileDetailAlpha == 0.40)
    }

    @Test("The hub's sizes equal the design's numbers")
    func hubSizes() {
        #expect(Tokens.Hub.pillHeight == 24)
        #expect(Tokens.Hub.pillFillAlpha == 0.09)
        #expect(Tokens.Hub.tileRadius == 14)
        #expect(Tokens.Hub.columns == 4)
        #expect(Tokens.Hub.tileGap == 6)
        #expect(Tokens.Hub.tilePadding == 10)
        // Hit targets of at least 24 points.
        #expect(Tokens.Hub.pillHeight >= Tokens.minimumTargetSize)
        #expect(Tokens.Island.gearSize >= Tokens.minimumTargetSize)
    }

    @Test("The island's numbers equal section 10b")
    func islandNumbers() {
        let island = Tokens.Island.self
        #expect(island.surface == .black)
        #expect(island.openTopRadius == 14)
        #expect(island.openBottomRadius == 40)
        #expect(island.liveTopRadius == 6)
        #expect(island.liveBottomRadius == 16)
        #expect(island.notchTopRadius == 6)
        #expect(island.notchBottomRadius == 10)
        #expect(island.baseWidth == 560)
        #expect(island.maximumWidth == 640)
        #expect(island.sidePadding == 16)
        #expect(island.contextGap == 8)
        #expect(island.contextRowHeight == 22)
        #expect(island.contextTextAlpha == 0.55)
        #expect(island.contextSymbolSize == 13)
        #expect(island.gearSize == 24)
        #expect(island.gearSymbolSize == 13)
        #expect(island.gearFillAlpha == 0.09)
        #expect(island.gearSymbolAlpha == 0.6)
        #expect(island.contentHeight == 110)
        #expect(island.overviewRowHeight == 92)
        #expect(island.overviewRowGap == 6)
        #expect(island.maximumContentHeight == 190)
        #expect(island.rowGap == 12)
        #expect(island.rowBottom == 12)
        #expect(island.buttonSizes == [30, 26])
        #expect(island.buttonGap == 6)
        #expect(island.buttonSymbolSize == 16)
        #expect(island.buttonIdleSymbolAlpha == 0.6)
        #expect(island.buttonIdleFillAlpha == 0.07)
        #expect(island.liveSideWidth == 90)
        #expect(island.liveSymbolSize == 16)
        #expect(island.liveValueSize == 12)
        #expect(island.edgeAlpha == 0.30)
        #expect(island.edgeWidth == 1)
        #expect(island.transitionMargin == 12)
        #expect(island.openWidthResponse == 0.42)
        #expect(island.openWidthDamping == 0.72)
        #expect(island.openHeightResponse == 0.48)
        #expect(island.openHeightDamping == 0.74)
        #expect(island.closeResponse == 0.34)
        #expect(island.closeDamping == 0.9)
        #expect(island.contentDelay == 0.09)
        #expect(island.contentInDuration == 0.3)
        #expect(island.contentOutDuration == 0.12)
        #expect(island.contentBlur == 10)
        #expect(island.contentScale == 0.94)
        #expect(island.contentCurve == [0.2, 0.8, 0.2, 1])
        #expect(island.switchDuration == 0.22)
        #expect(island.switchRise == 4)
    }

    @Test("The island keeps the concept's relations")
    func islandRelations() {
        let island = Tokens.Island.self
        for size in island.buttonSizes + [island.gearSize] {
            #expect(size >= Tokens.minimumTargetSize)
        }
        #expect(island.buttonSizes.first == 30)
        #expect(island.buttonSizes == island.buttonSizes.sorted(by: >))
        #expect(island.maximumWidth >= island.baseWidth)
        #expect(2 * island.overviewRowHeight + island.overviewRowGap == island.maximumContentHeight)
        #expect(island.contentHeight <= island.maximumContentHeight)
        #expect(island.openWidthDamping < 1)
        #expect(island.openHeightDamping < 1)
        #expect(island.closeDamping > island.openWidthDamping)
        #expect(island.contentScale < 1)
    }

    @Test("The floating bar's shadow is the design's numbers and fits the panel's insets")
    func floatingBarShadow() {
        #expect(Tokens.Shadow.barOpacity == 0.30)
        #expect(Tokens.Shadow.barRadius == 10)
        #expect(Tokens.Shadow.barOffsetY == 4)
        let insets = HolzBarShelfPlacement.floatingInsets
        // The blur reaches its radius to every side and the drop pushes it down.
        #expect(Tokens.Shadow.barRadius + Tokens.Shadow.barOffsetY <= insets.bottom)
        #expect(Tokens.Shadow.barRadius <= insets.leading)
        #expect(Tokens.Shadow.barRadius <= insets.trailing)
    }

    @Test("The settings kit measures are the approved ones")
    func settingsKitMeasures() {
        #expect(Tokens.SettingsKit.rowMinHeight == 30)
        #expect(Tokens.SettingsKit.rowPaddingVertical == 3)
        #expect(Tokens.SettingsKit.rowPaddingHorizontal == 12)
        #expect(Tokens.SettingsKit.labelControlGap == 16)
        #expect(Tokens.SettingsKit.accessoryGap == 6)
        #expect(Tokens.SettingsKit.subRowInset == 18)
        #expect(Tokens.SettingsKit.dependentOpacity == 0.42)
        #expect(Tokens.SettingsKit.switchMinHeight == Tokens.minimumTargetSize)
        #expect(Tokens.SettingsKit.groupHeaderInset == 4)
        #expect(Tokens.SettingsKit.groupHeaderGap == 6)
        #expect(Tokens.SettingsKit.groupGap == 14)
        #expect(Tokens.SettingsKit.footnoteGap == 6)
        #expect(Tokens.SettingsKit.footnoteInset == 4)
        #expect(Tokens.SettingsKit.popUpMaxWidth == 260)
        #expect(Tokens.SettingsKit.sliderTrackWidth == 120)
        #expect(Tokens.SettingsKit.sliderValueGap == 10)
        #expect(Tokens.SettingsKit.sliderValueMinWidth == 34)
        #expect(Tokens.SettingsKit.stepperValueGap == 6)
        #expect(Tokens.SettingsKit.textFieldMinWidth == 150)
        #expect(Tokens.SettingsKit.colorWellWidth == 40)
        #expect(Tokens.SettingsKit.colorWellHeight == 20)
        #expect(Tokens.SettingsKit.colorWellRadius == 6)
        #expect(Tokens.SettingsKit.gradientStripWidth == 96)
        #expect(Tokens.SettingsKit.hotkeyRecorderWidth == 132)
        #expect(Tokens.SettingsKit.hotkeyRecorderHeight == 24)
        #expect(Tokens.SettingsKit.stateLineGap == 8)
        #expect(Tokens.SettingsKit.noteLinePaddingVertical == 8)
        #expect(Tokens.SettingsKit.noteLinePaddingHorizontal == 12)
        #expect(Tokens.SettingsKit.disclosureChevronSize == 10)
        #expect(Tokens.SettingsKit.moduleRowMinHeight == 38)
        #expect(Tokens.SettingsKit.moduleRowGap == 10)
        #expect(Tokens.SettingsKit.moduleTileSize == 24)
        #expect(Tokens.SettingsKit.moduleTileRadius == 7)
        #expect(Tokens.SettingsKit.moduleSymbolSize == 14)
        #expect(Tokens.SettingsKit.moduleChevronButtonSize == 22)
        #expect(Tokens.SettingsKit.moduleChevronSize == 10)
        #expect(Tokens.SettingsKit.openAreaInset == 46)
        #expect(Tokens.SettingsKit.accentFillLight == 0.12)
        #expect(Tokens.SettingsKit.accentFillDark == 0.16)
        #expect(Tokens.SettingsKit.openAreaFillLight == 0.07)
        #expect(Tokens.SettingsKit.openAreaFillDark == 0.08)
        #expect(Tokens.SettingsKit.infoButtonSize == 14)
        #expect(Tokens.SettingsKit.infoButtonLineWidth == 1.3)
        #expect(Tokens.SettingsKit.infoButtonHitArea == 28)
        #expect(Tokens.SettingsKit.infoPopoverMaxWidth == 290)
        #expect(Tokens.SettingsKit.infoPopoverPaddingVertical == 10)
        #expect(Tokens.SettingsKit.infoPopoverPaddingHorizontal == 12)
        #expect(Tokens.SettingsKit.infoTextMaxCharacters == 200)
        #expect(Tokens.SettingsKit.smallTextMaxWords == 3)
        #expect(Tokens.SettingsKit.pictureCardGap == 10)
        #expect(Tokens.SettingsKit.pictureCardRowPaddingVertical == 10)
        #expect(Tokens.SettingsKit.pictureCardRowPaddingHorizontal == 12)
        #expect(Tokens.SettingsKit.pictureCardStrokeWidth == 1.5)
        #expect(Tokens.SettingsKit.pictureCardPadding == 8)
        #expect(Tokens.SettingsKit.pictureWellHeight == 42)
        #expect(Tokens.SettingsKit.pictureWellRadius == 6)
        #expect(Tokens.SettingsKit.pictureCardCompactWidth == 78)
        #expect(Tokens.SettingsKit.pictureCardsBeforeCompact == 4)
        #expect(Tokens.SettingsKit.paneMarginHorizontal == 20)
        #expect(Tokens.SettingsKit.paneMarginTop == 4)
        #expect(Tokens.SettingsKit.paneMarginBottom == 22)
    }

    @Test("The settings sidebar follows the system size with the approved medium")
    func settingsSidebarMeasures() {
        typealias Metrics = Tokens.SettingsSidebar.Metrics
        #expect(Tokens.SettingsSidebar.medium == Metrics(width: 210, textSize: 14, symbolSize: 22, rowHeight: 32))
        let small = Tokens.SettingsSidebar.small
        let medium = Tokens.SettingsSidebar.medium
        let large = Tokens.SettingsSidebar.large
        #expect(small.width < medium.width && medium.width < large.width)
        #expect(small.textSize < medium.textSize && medium.textSize < large.textSize)
        #expect(small.symbolSize < medium.symbolSize && medium.symbolSize < large.symbolSize)
        #expect(small.rowHeight < medium.rowHeight && medium.rowHeight < large.rowHeight)
        #expect(Tokens.SettingsSidebar.rowRadius == Tokens.Radius.control)
        #expect(Tokens.SettingsSidebar.rowPadding == 10)
        #expect(Tokens.SettingsSidebar.symbolTextGap == 10)
        #expect(Tokens.SettingsSidebar.rowGap == 2)
        #expect(Tokens.SettingsSidebar.moduleGap == 10)
        #expect(Tokens.SettingsSidebar.searchFieldHeight == 28)
        #expect(Tokens.SettingsSidebar.searchMagnifierSize == 13)
        #expect(Tokens.SettingsSidebar.searchFieldBottomGap == 8)
        #expect(Tokens.SettingsSidebar.titleBarHeight == 44)
        #expect(Tokens.SettingsSidebar.minimumWindowWidth == 760)
        #expect(Tokens.SettingsSidebar.minimumWindowHeight == 540)
    }

    @Test("The settings kit fits its own parts")
    func settingsKitFits() {
        typealias Kit = Tokens.SettingsKit
        #expect(Kit.rowMinHeight >= Kit.hotkeyRecorderHeight)
        #expect(Tokens.Spacing.sm + Kit.subRowInset == 30)
        #expect(Kit.rowPaddingHorizontal + Kit.subRowInset == 30)
        #expect(Kit.infoButtonHitArea >= 28)
        #expect(Kit.switchMinHeight >= Tokens.minimumTargetSize)
        #expect(Tokens.SettingsSidebar.rowRadius == Tokens.Radius.control)
    }

    @Test("The onboarding keeps its measures")
    func onboardingMeasures() {
        #expect(Tokens.Onboarding.width == 440)
        #expect(Tokens.Onboarding.pictureHeight == 44)
        #expect(Tokens.Onboarding.dotSize == 6)
    }

    @Test("The Layout list keeps the measures of mock-up 01")
    func layoutListMeasures() {
        let list = Tokens.LayoutList.self
        #expect(list.appColumnWidth == 150)
        #expect(list.sectionColumnWidth == 150)
        #expect(list.iconSize == 20)
        #expect(list.filterFieldMinWidth == 112)
        #expect(list.filteredOutOpacity == 0.25)
        #expect(list.siblingRingWidth == 2)
    }

    @Test("The undo toast keeps the measures of the design concept")
    func undoToastMeasures() {
        let toast = Tokens.UndoToast.self
        #expect(toast.paddingVertical == 7)
        #expect(toast.paddingHorizontal == 12)
        #expect(toast.gap == 10)
        #expect(toast.visibleSeconds == 5)
        #expect(toast.plainVisibleSeconds == 3)
        #expect(toast.menuBarGap == 8)
        #expect(toast.screenMargin == 8)
    }
}
