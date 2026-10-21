import Testing
@testable import HolzBarCore

@Suite("DesignTokens")
struct DesignTokensTests {
    private typealias Tokens = DesignTokens

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

    @Test("Radii ascend from control to hub")
    func radii() {
        let radii = [
            Tokens.Radius.keyCap, Tokens.Radius.control, Tokens.Radius.card,
            Tokens.Radius.panel, Tokens.Radius.hub
        ]
        #expect(radii == radii.sorted())
    }
}
