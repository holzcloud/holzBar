import Foundation
import Testing
@testable import HolzBarCore

@Suite("BuiltInItem")
struct BuiltInItemTests {
    @Test("Raw values are stored and stay")
    func rawValues() {
        #expect(BuiltInItem.focus.rawValue == "focus")
        #expect(BuiltInItem.airDrop.rawValue == "airDrop")
        #expect(BuiltInItem.media.rawValue == "media")
        #expect(BuiltInItem.userSwitching.rawValue == "userSwitching")
        #expect(BuiltInItem.timer.rawValue == "timer")
        #expect(BuiltInItem.launcher.rawValue == "launcher")
        #expect(BuiltInItem.allCases.count == 6)
    }

    @Test("Only the timer and the launcher can be added more than once")
    func several() {
        #expect(BuiltInItem.allCases.filter(\.allowsSeveral) == [.timer, .launcher])
    }

    @Test("Every item has a symbol; only Focus and fast user switching have a settings pane")
    func symbolsAndPanes() {
        for item in BuiltInItem.allCases {
            #expect(!item.symbolName.isEmpty)
        }
        #expect(BuiltInItem.allCases.filter { $0.settingsPaneURL != nil } == [.focus, .userSwitching])
        #expect(BuiltInItem.focus.settingsPaneURL?.scheme == "x-apple.systempreferences")
    }

    @Test("Apple's item is found by its words, in an Apple namespace only")
    func appleItemMatching() {
        #expect(BuiltInItem.focus.matchesAppleItem(key: "com.apple.controlcenter:FocusModes"))
        #expect(BuiltInItem.airDrop.matchesAppleItem(key: "com.apple.controlcenter:AirDrop"))
        #expect(BuiltInItem.userSwitching.matchesAppleItem(key: "com.apple.controlcenter:UserSwitcher"))
        #expect(!BuiltInItem.focus.matchesAppleItem(key: "com.example.app:Focus"))
        #expect(!BuiltInItem.focus.matchesAppleItem(key: "com.apple.controlcenter:Wi-Fi"))
        // The numbered system items are never Apple's item to open.
        #expect(!BuiltInItem.focus.matchesAppleItem(key: "com.apple.MenuBarAgent:Focus"))
        for item in [BuiltInItem.media, .timer, .launcher] {
            #expect(!item.matchesAppleItem(key: "com.apple.controlcenter:FocusModes"))
        }
    }

    @Test("The first matching key is taken, in the order given")
    func firstKey() {
        let keys = ["com.apple.controlcenter:Wi-Fi", "com.apple.controlcenter:AirDrop", "com.apple.airport:AirDrop2"]
        #expect(BuiltInItem.airDrop.appleItemKey(in: keys) == "com.apple.controlcenter:AirDrop")
        #expect(BuiltInItem.focus.appleItemKey(in: keys) == nil)
    }
}

@Suite("MediaKey")
struct MediaKeyTests {
    @Test("The key codes are the system's")
    func codes() {
        #expect(MediaKey.playPause.rawValue == 16)
        #expect(MediaKey.next.rawValue == 17)
        #expect(MediaKey.previous.rawValue == 18)
        #expect(MediaKey.systemDefinedSubtype == 8)
    }

    @Test("The event data holds the key code and the state")
    func data() {
        #expect(MediaKey.playPause.eventData(isDown: true) == 0x10_0A00)
        #expect(MediaKey.playPause.eventData(isDown: false) == 0x10_0B00)
        #expect(MediaKey.next.eventData(isDown: true) == 0x11_0A00)
        #expect(MediaKey.previous.eventData(isDown: false) == 0x12_0B00)
        #expect(MediaKey.modifierBits(isDown: true) == 0xA00)
        #expect(MediaKey.modifierBits(isDown: false) == 0xB00)
    }
}

@Suite("MediaVisibility")
struct MediaVisibilityTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let grace = MediaVisibility.gracePeriod

    @Test("Always shown when the setting is off")
    func always() {
        #expect(MediaVisibility.isShown(onlyWhenActive: false, isActive: false, lastActive: nil, now: now))
        #expect(MediaVisibility.nextChange(onlyWhenActive: false, isActive: false, lastActive: now, now: now) == nil)
    }

    @Test("Shown while sound plays")
    func active() {
        #expect(MediaVisibility.isShown(onlyWhenActive: true, isActive: true, lastActive: nil, now: now))
        #expect(MediaVisibility.nextChange(onlyWhenActive: true, isActive: true, lastActive: now, now: now) == nil)
    }

    @Test("Hidden when sound never played, and after the grace period")
    func idle() {
        #expect(!MediaVisibility.isShown(onlyWhenActive: true, isActive: false, lastActive: nil, now: now))
        let stopped = now.addingTimeInterval(-10)
        #expect(MediaVisibility.isShown(onlyWhenActive: true, isActive: false, lastActive: stopped, now: now))
        #expect(MediaVisibility.nextChange(onlyWhenActive: true, isActive: false, lastActive: stopped, now: now) == stopped.addingTimeInterval(grace))
        let longAgo = now.addingTimeInterval(-grace)
        #expect(!MediaVisibility.isShown(onlyWhenActive: true, isActive: false, lastActive: longAgo, now: now))
        #expect(MediaVisibility.nextChange(onlyWhenActive: true, isActive: false, lastActive: longAgo, now: now) == nil)
    }
}
