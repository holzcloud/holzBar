import Testing
@testable import HolzBarCore

@Suite("TransparencyTreatment")
struct TransparencyTreatmentTests {
    private let reduce = TransparencyOptions(reduceTransparency: true)
    private let contrast = TransparencyOptions(increaseContrast: true)
    private let both = TransparencyOptions(reduceTransparency: true, increaseContrast: true)
    private let neither = TransparencyOptions()

    @Test("With both options off nothing changes, whatever the border setting", arguments: [false, true])
    func bothOffLeavesSurfacesUnchanged(hasConfiguredBorder: Bool) {
        #expect(TransparencyTreatment.menuBar(isGlass: true, options: neither, hasConfiguredBorder: hasConfiguredBorder) == .unchanged)
        #expect(TransparencyTreatment.shelf(options: neither, hasConfiguredBorder: hasConfiguredBorder) == .unchanged)
    }

    @Test("Each option makes System Glass and the Shelf opaque with a visible border")
    func optionsMakeSurfacesOpaqueWithBorder() {
        for options in [reduce, contrast, both] {
            let glass = TransparencyTreatment.menuBar(isGlass: true, options: options, hasConfiguredBorder: false)
            let shelf = TransparencyTreatment.shelf(options: options, hasConfiguredBorder: false)
            #expect(glass.fill == .opaque)
            #expect(glass.border == .visible)
            #expect(glass.borderOpacity > 0)
            #expect(shelf == glass)
        }
    }

    @Test("A menu bar tint that is not glass is unchanged under every combination", arguments: [false, true])
    func nonGlassTintIsUnchanged(hasConfiguredBorder: Bool) {
        for options in [neither, reduce, contrast, both] {
            #expect(TransparencyTreatment.menuBar(isGlass: false, options: options, hasConfiguredBorder: hasConfiguredBorder) == .unchanged)
        }
    }

    @Test("A configured border stays, and the fill is still opaque")
    func configuredBorderStays() {
        for options in [reduce, contrast, both] {
            let glass = TransparencyTreatment.menuBar(isGlass: true, options: options, hasConfiguredBorder: true)
            let shelf = TransparencyTreatment.shelf(options: options, hasConfiguredBorder: true)
            #expect(glass.fill == .opaque)
            #expect(glass.border == .asConfigured)
            #expect(glass.borderOpacity == 0)
            #expect(shelf == glass)
        }
    }

    @Test("Increase Contrast draws a bolder line than Reduce Transparency alone, and both equal Increase Contrast")
    func increaseContrastIsBolder() {
        let reduceOnly = TransparencyTreatment.shelf(options: reduce, hasConfiguredBorder: false)
        let contrastOnly = TransparencyTreatment.shelf(options: contrast, hasConfiguredBorder: false)
        let bothOn = TransparencyTreatment.shelf(options: both, hasConfiguredBorder: false)
        #expect(contrastOnly.borderOpacity > reduceOnly.borderOpacity)
        #expect(bothOn == contrastOnly)
        #expect(TransparencyTreatment.visibleBorderWidth > 0)
    }

    @Test("prefersOpaque is true exactly when either option is on")
    func prefersOpaque() {
        #expect(!neither.prefersOpaque)
        #expect(reduce.prefersOpaque)
        #expect(contrast.prefersOpaque)
        #expect(both.prefersOpaque)
    }
}
