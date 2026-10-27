import Testing
@testable import HolzBarCore

@Suite("RevealAnimationPolicy")
struct RevealAnimationPolicyTests {
    private let backends: [MenuBarBackendKind] = [.windowList, .service26, .accessibility27]

    @Test("Only macOS 26 supports stepping the divider")
    func supported() {
        #expect(RevealAnimationPolicy.supportsDividerSteps(.service26))
        #expect(!RevealAnimationPolicy.supportsDividerSteps(.windowList))
        #expect(!RevealAnimationPolicy.supportsDividerSteps(.accessibility27))
    }

    @Test("On macOS 26 the divider steps in the smooth style with Reduce Motion off and no drag")
    func steps() {
        #expect(RevealAnimationPolicy.stepsDivider(
            style: .smooth, reduceMotion: false, backend: .service26, isDraggingItem: false
        ))
    }

    @Test("The instant and fade styles never step the divider, on any backend")
    func otherStyles() {
        for style in [RevealAnimationStyle.instant, .fade] {
            for backend in backends {
                #expect(!RevealAnimationPolicy.stepsDivider(
                    style: style, reduceMotion: false, backend: backend, isDraggingItem: false
                ))
            }
        }
    }

    @Test("Reduce Motion wins over the setting on any backend")
    func reduceMotion() {
        for backend in backends {
            #expect(!RevealAnimationPolicy.stepsDivider(
                style: .smooth, reduceMotion: true, backend: backend, isDraggingItem: false
            ))
        }
    }

    @Test("Nothing steps while an item is dragged")
    func dragging() {
        for backend in backends {
            #expect(!RevealAnimationPolicy.stepsDivider(
                style: .smooth, reduceMotion: false, backend: backend, isDraggingItem: true
            ))
        }
    }

    @Test("macOS 14, 15 and 27 keep what they do today")
    func otherBackends() {
        for backend in [MenuBarBackendKind.windowList, .accessibility27] {
            #expect(!RevealAnimationPolicy.stepsDivider(
                style: .smooth, reduceMotion: false, backend: backend, isDraggingItem: false
            ))
        }
    }
}
