import Testing
@testable import HolzBarCore

@Suite("NotchHubPolicy")
struct NotchHubPolicyTests {
    typealias Policy = NotchHubPolicy

    private let clear = Policy.Environment(
        isFullscreenSpace: false,
        isMenuBarHiddenBySystem: false,
        isPresenting: false,
        isDisplayAllowed: true
    )

    private let inZone = Policy.Pointer(isInZone: true, isInHub: false)
    private let inHub = Policy.Pointer(isInZone: false, isInHub: true)
    private let away = Policy.Pointer(isInZone: false, isInHub: false)

    @Test("Nothing in the way gives no block reason, for either trigger")
    func nothingInTheWay() {
        #expect(Policy.blockReason(clear, trigger: .hover) == nil)
        #expect(Policy.blockReason(clear, trigger: .hotkey) == nil)
    }

    @Test("Each flag alone gives its reason")
    func eachFlagAlone() {
        var excluded = clear
        excluded.isDisplayAllowed = false
        #expect(Policy.blockReason(excluded, trigger: .hover) == .displayNotAllowed)
        #expect(Policy.blockReason(excluded, trigger: .hotkey) == .displayNotAllowed)
        var fullscreen = clear
        fullscreen.isFullscreenSpace = true
        #expect(Policy.blockReason(fullscreen, trigger: .hover) == .fullscreen)
        var hidden = clear
        hidden.isMenuBarHiddenBySystem = true
        #expect(Policy.blockReason(hidden, trigger: .hover) == .menuBarHidden)
        var presenting = clear
        presenting.isPresenting = true
        #expect(Policy.blockReason(presenting, trigger: .hover) == .presenting)
    }

    @Test("Several flags give the first reason in order")
    func order() {
        let all = Policy.Environment(
            isFullscreenSpace: true,
            isMenuBarHiddenBySystem: true,
            isPresenting: true,
            isDisplayAllowed: false
        )
        #expect(Policy.blockReason(all, trigger: .hover) == .displayNotAllowed)
        var allowed = all
        allowed.isDisplayAllowed = true
        #expect(Policy.blockReason(allowed, trigger: .hover) == .fullscreen)
        allowed.isFullscreenSpace = false
        #expect(Policy.blockReason(allowed, trigger: .hover) == .menuBarHidden)
        allowed.isMenuBarHiddenBySystem = false
        #expect(Policy.blockReason(allowed, trigger: .hover) == .presenting)
    }

    @Test("The hotkey is blocked in a fullscreen space and with the menu bar hidden, and a presented screen blocks both")
    func hotkeyAndPresenting() {
        #expect(!Policy.hotkeyOpensInFullscreen)
        #expect(Policy.blocksWhilePresenting)
        var fullscreen = clear
        fullscreen.isFullscreenSpace = true
        #expect(Policy.blockReason(fullscreen, trigger: .hotkey) == .fullscreen)
        var hidden = clear
        hidden.isMenuBarHiddenBySystem = true
        #expect(Policy.blockReason(hidden, trigger: .hotkey) == .menuBarHidden)
        var presenting = clear
        presenting.isPresenting = true
        #expect(Policy.blockReason(presenting, trigger: .hover) == .presenting)
        #expect(Policy.blockReason(presenting, trigger: .hotkey) == .presenting)
    }

    @Test("A closed hub opens when the pointer is in the zone, and not otherwise")
    func closedHub() {
        #expect(Policy.hoverDesired(pointer: inZone, isOpen: false, closesOnLeave: true) == .open)
        #expect(Policy.hoverDesired(pointer: away, isOpen: false, closesOnLeave: true) == nil)
        #expect(Policy.hoverDesired(pointer: inHub, isOpen: false, closesOnLeave: true) == nil)
    }

    @Test("An open hub closes only when the pointer is in neither the hub nor the zone, and only if it closes on leaving")
    func openHub() {
        #expect(Policy.hoverDesired(pointer: inHub, isOpen: true, closesOnLeave: true) == nil)
        #expect(Policy.hoverDesired(pointer: inZone, isOpen: true, closesOnLeave: true) == nil)
        #expect(Policy.hoverDesired(pointer: away, isOpen: true, closesOnLeave: true) == .close)
        #expect(Policy.hoverDesired(pointer: away, isOpen: true, closesOnLeave: false) == nil)
    }

    @Test("An open request schedules once, and the same request while pending changes nothing")
    func scheduling() {
        #expect(
            Policy.hoverDecision(pointer: inZone, isOpen: false, closesOnLeave: true, pending: nil)
                == .schedule(.open)
        )
        #expect(
            Policy.hoverDecision(pointer: inZone, isOpen: false, closesOnLeave: true, pending: .open)
                == Policy.HoverDecision.none
        )
    }

    @Test("Leaving the zone while an open is pending cancels it")
    func cancelling() {
        #expect(
            Policy.hoverDecision(pointer: away, isOpen: false, closesOnLeave: true, pending: .open)
                == .cancelPending
        )
        // The pointer comes back to a hub that was about to close.
        #expect(
            Policy.hoverDecision(pointer: inHub, isOpen: true, closesOnLeave: true, pending: .close)
                == .cancelPending
        )
    }

    @Test("A close request is not rescheduled while pending, and replaces a pending open")
    func closeRequests() {
        #expect(
            Policy.hoverDecision(pointer: away, isOpen: true, closesOnLeave: true, pending: .close)
                == Policy.HoverDecision.none
        )
        #expect(
            Policy.hoverDecision(pointer: away, isOpen: true, closesOnLeave: true, pending: .open)
                == .schedule(.close)
        )
        #expect(
            Policy.hoverDecision(pointer: away, isOpen: true, closesOnLeave: true, pending: nil)
                == .schedule(.close)
        )
    }

    @Test("Nothing desired and nothing pending is none")
    func idle() {
        #expect(
            Policy.hoverDecision(pointer: away, isOpen: false, closesOnLeave: true, pending: nil)
                == Policy.HoverDecision.none
        )
        #expect(
            Policy.hoverDecision(pointer: away, isOpen: true, closesOnLeave: false, pending: nil)
                == Policy.HoverDecision.none
        )
    }

    @Test("The delays are a quarter and four tenths of a second")
    func delays() {
        #expect(Policy.openDelay == .milliseconds(250))
        #expect(Policy.closeDelay == .milliseconds(400))
    }

    @Test("A global point maps to the display's top-left origin, and the top edge is y 0 and inside a zone that starts there")
    func localPoint() {
        let point = Policy.localPoint(globalX: 1500, globalY: 900, displayMinX: 1440, displayMaxY: 982)
        #expect(point.x == 60)
        #expect(point.y == 82)
        let top = Policy.localPoint(globalX: 756, globalY: 982, displayMinX: 0, displayMaxY: 982)
        #expect(top.y == 0)
        let zone = NotchHubGeometry.Rect(x: 663, y: 0, width: 186, height: 32)
        #expect(zone.contains(x: top.x, y: top.y))
    }

    @Test("The capsule's trigger is judged exactly as a hover is, in every environment")
    func compactTriggerEqualsHover() {
        let flags = [false, true]
        for fullscreen in flags {
            for hidden in flags {
                for presenting in flags {
                    for allowed in flags {
                        let environment = Policy.Environment(
                            isFullscreenSpace: fullscreen,
                            isMenuBarHiddenBySystem: hidden,
                            isPresenting: presenting,
                            isDisplayAllowed: allowed
                        )
                        #expect(
                            Policy.blockReason(environment, trigger: .compact)
                                == Policy.blockReason(environment, trigger: .hover)
                        )
                    }
                }
            }
        }
        var fullscreen = clear
        fullscreen.isFullscreenSpace = true
        #expect(Policy.blockReason(fullscreen, trigger: .compact) == .fullscreen)
        #expect(Policy.blockReason(clear, trigger: .compact) == nil)
    }

    @Test("A hub opened from the capsule closes on leaving like one opened by hover, and the hotkey's does not")
    func compactClosesOnLeave() {
        #expect(Policy.Trigger.compact.closesOnLeave)
        #expect(Policy.Trigger.hover.closesOnLeave)
        #expect(!Policy.Trigger.hotkey.closesOnLeave)
        // The pointer rule itself is unchanged: in the zone (extended by the capsule) it opens,
        // and away from both it closes a hub that closes on leaving.
        #expect(Policy.hoverDesired(pointer: inZone, isOpen: false, closesOnLeave: false) == .open)
        #expect(
            Policy.hoverDesired(pointer: away, isOpen: true, closesOnLeave: Policy.Trigger.compact.closesOnLeave)
                == .close
        )
    }

    @Test("A file drag is judged exactly as a hover is, in every environment")
    func fileDragTriggerEqualsHover() {
        let flags = [false, true]
        for fullscreen in flags {
            for hidden in flags {
                for presenting in flags {
                    for allowed in flags {
                        let environment = Policy.Environment(
                            isFullscreenSpace: fullscreen,
                            isMenuBarHiddenBySystem: hidden,
                            isPresenting: presenting,
                            isDisplayAllowed: allowed
                        )
                        #expect(
                            Policy.blockReason(environment, trigger: .fileDrag)
                                == Policy.blockReason(environment, trigger: .hover)
                        )
                    }
                }
            }
        }
        #expect(Policy.Trigger.fileDrag.closesOnLeave)
    }

    @Test("A wish and the pending action decide what to schedule")
    func decisionTruthTable() {
        #expect(Policy.decision(desired: .open, pending: nil) == .schedule(.open))
        #expect(Policy.decision(desired: .open, pending: .open) == .none)
        #expect(Policy.decision(desired: nil, pending: .open) == .cancelPending)
        #expect(Policy.decision(desired: nil, pending: .close) == .cancelPending)
        #expect(Policy.decision(desired: .close, pending: .open) == .schedule(.close))
        #expect(Policy.decision(desired: .close, pending: .close) == .none)
        #expect(Policy.decision(desired: .close, pending: nil) == .schedule(.close))
        #expect(Policy.decision(desired: nil, pending: nil) == .none)
    }
}
