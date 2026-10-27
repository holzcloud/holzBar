import Testing

@testable import HolzBarCore

@Suite("RevealAnimationStyle")
struct RevealAnimationStyleTests {
    @Test("The raw values stay as stored")
    func rawValues() {
        #expect(RevealAnimationStyle.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(RevealAnimationStyle.instant.rawValue == 0)
        #expect(RevealAnimationStyle.smooth.rawValue == 1)
        #expect(RevealAnimationStyle.fade.rawValue == 2)
    }

    @Test("A stored number that names no style means the standard one")
    func stored() {
        #expect(RevealAnimationStyle.stored(0) == .instant)
        #expect(RevealAnimationStyle.stored(1) == .smooth)
        #expect(RevealAnimationStyle.stored(2) == .fade)
        #expect(RevealAnimationStyle.stored(3) == .standard)
        #expect(RevealAnimationStyle.stored(-1) == .standard)
        #expect(RevealAnimationStyle.standard == .smooth)
    }

    @Test("The two switches of earlier versions become one style")
    func migration() {
        #expect(RevealAnimationStyle.migrated(animatesShowHide: nil, animatesShelf: nil) == .smooth)
        #expect(RevealAnimationStyle.migrated(animatesShowHide: true, animatesShelf: true) == .smooth)
        #expect(RevealAnimationStyle.migrated(animatesShowHide: true, animatesShelf: false) == .smooth)
        #expect(RevealAnimationStyle.migrated(animatesShowHide: false, animatesShelf: true) == .fade)
        #expect(RevealAnimationStyle.migrated(animatesShowHide: false, animatesShelf: nil) == .fade)
        #expect(RevealAnimationStyle.migrated(animatesShowHide: false, animatesShelf: false) == .instant)
    }

    @Test("Only the smooth style slides the bar")
    func slidesBar() {
        #expect(RevealAnimationStyle.smooth.slidesBar)
        #expect(!RevealAnimationStyle.fade.slidesBar)
        #expect(!RevealAnimationStyle.instant.slidesBar)
    }
}

@Suite("The holzBar Shelf's animation")
struct ShelfAnimationTests {
    @Test("Instant appears at once")
    func instant() {
        let plan = ShelfAnimation.plan(style: .instant, reduceMotion: false)
        #expect(plan.isInstant)
        #expect(plan == .instant)
    }

    @Test("Fade only fades, in a moment")
    func fade() {
        let plan = ShelfAnimation.plan(style: .fade, reduceMotion: false)
        let isShort = plan.fadeDuration > 0 && plan.fadeDuration <= ShelfAnimation.longestDuration
        #expect(isShort)
        #expect(plan.slideDistance == 0)
        #expect(!plan.isInstant)
    }

    @Test("Smooth fades and slides, and takes the longest")
    func smooth() {
        let plan = ShelfAnimation.plan(style: .smooth, reduceMotion: false)
        let fade = ShelfAnimation.plan(style: .fade, reduceMotion: false)
        let isShort = plan.fadeDuration > fade.fadeDuration && plan.fadeDuration <= ShelfAnimation.longestDuration
        let slidesALittle = plan.slideDistance > 0 && plan.slideDistance <= 16
        #expect(isShort)
        #expect(slidesALittle)
        #expect(!plan.isInstant)
    }

    @Test("Reduce Motion wins over every style")
    func reduceMotion() {
        for style in RevealAnimationStyle.allCases {
            #expect(ShelfAnimation.plan(style: style, reduceMotion: true).isInstant)
        }
    }
}
