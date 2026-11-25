import Testing
@testable import HolzBarCore

@Suite("HubPin")
struct HubPinTests {
    private static let passive: [HubPin.CloseReason] = [.outsideClick, .pointerLeft]
    private static let commands: [HubPin.CloseReason] = [
        .escape, .hotkey, .gesture, .spaceChange, .displayChange, .settings, .moduleOff,
    ]

    @Test("A pin that is not set allows every reason")
    func unpinnedAllowsEverything() {
        for reason in Self.passive + Self.commands {
            var pin = HubPin()
            let allowed = pin.allowsClose(reason)
            #expect(allowed)
            #expect(!pin.isPinned)
        }
    }

    @Test("A pinned hub refuses the outside click and the pointer leaving, and stays pinned")
    func pinnedRefusesPassiveCloses() {
        for reason in Self.passive {
            var pin = HubPin()
            pin.toggle()
            let allowed = pin.allowsClose(reason)
            #expect(!allowed)
            #expect(pin.isPinned)
        }
    }

    @Test("A refusal never unpins, however often it happens")
    func refusalKeepsThePin() {
        var pin = HubPin()
        pin.toggle()
        let first = pin.allowsClose(.outsideClick)
        let second = pin.allowsClose(.pointerLeft)
        let third = pin.allowsClose(.outsideClick)
        #expect(!first && !second && !third)
        #expect(pin.isPinned)
    }

    @Test("A pinned hub allows every explicit command and unpins")
    func pinnedAllowsCommands() {
        for reason in Self.commands {
            var pin = HubPin()
            pin.toggle()
            let allowed = pin.allowsClose(reason)
            #expect(allowed)
            #expect(!pin.isPinned)
        }
    }

    @Test("Esc closes a pinned hub in one press (D-27)")
    func escapeUnpinsAndCloses() {
        var pin = HubPin()
        pin.toggle()
        let allowed = pin.allowsClose(.escape)
        #expect(allowed)
        #expect(!pin.isPinned)
    }

    @Test("Toggling twice leaves the hub unpinned, once pinned")
    func toggleFlips() {
        var pin = HubPin()
        pin.toggle()
        #expect(pin.isPinned)
        pin.toggle()
        #expect(!pin.isPinned)
    }

    @Test("Unpinning an unpinned pin changes nothing, and unpinning a pinned one clears it")
    func unpinIsIdempotent() {
        var pin = HubPin()
        pin.unpin()
        #expect(pin == HubPin())
        pin.toggle()
        pin.unpin()
        pin.unpin()
        #expect(!pin.isPinned)
    }
}
