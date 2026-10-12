import Testing
@testable import HolzBarCore

@Suite("PinnedSystemItems")
struct PinnedSystemItemsTests {
    @Test("The essentials of Control Center are pinned")
    func pinned() {
        #expect(PinnedSystemItems.isPinned(key: "com.apple.controlcenter:Clock"))
        #expect(PinnedSystemItems.isPinned(key: "com.apple.controlcenter:WiFi"))
        #expect(PinnedSystemItems.isPinned(key: "com.apple.controlcenter:BentoBox"))
        #expect(PinnedSystemItems.isPinned(key: "com.apple.controlcenter:Battery:2"))
    }

    @Test("Other items are not pinned")
    func notPinned() {
        #expect(!PinnedSystemItems.isPinned(key: "com.apple.controlcenter:Bluetooth"))
        #expect(!PinnedSystemItems.isPinned(key: "com.example.app:Clock"))
        #expect(!PinnedSystemItems.isPinned(key: "Clock"))
        #expect(!PinnedSystemItems.isPinned(key: ""))
    }

    @Test("A pinned item is never wanted outside the visible section")
    func filter() {
        let wanted = [
            "com.apple.controlcenter:Clock": 1,
            "com.apple.controlcenter:Battery": 0,
            "com.example.app:Tool": 2,
        ]
        let kept = PinnedSystemItems.keepingPinnedVisible(wanted)
        #expect(kept == ["com.apple.controlcenter:Battery": 0, "com.example.app:Tool": 2])
    }
}
