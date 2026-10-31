import Foundation
import Testing
@testable import HolzBarCore

@Suite("AccessoryBattery")
struct AccessoryBatteryTests {
    private func description(
        name: Any? = "Magic Mouse",
        current: Any? = 90,
        maximum: Any? = 100,
        warn: Any? = 20,
        category: Any? = "Mouse",
        identifier: Any? = "A1B2C3D4-0000-4000-8000-000000000001",
        type: Any? = "Accessory Source"
    ) -> [String: Any] {
        var result = [String: Any]()
        result["Type"] = type
        result["Name"] = name
        result["Current Capacity"] = current
        result["Max Capacity"] = maximum
        result["Low Warn Level"] = warn
        result["Accessory Category"] = category
        result["Accessory Identifier"] = identifier
        return result
    }

    @Test("A complete accessory description becomes a battery")
    func parsesACompleteDescription() {
        let battery = AccessoryBatteryReading.battery(from: description())
        #expect(battery?.name == "Magic Mouse")
        #expect(battery?.percent == 90)
        #expect(battery?.lowWarnLevel == 20)
        #expect(battery?.category == "Mouse")
        #expect(battery?.id == "A1B2C3D4-0000-4000-8000-000000000001")
    }

    @Test("Anything that is not an accessory source with a name and two capacities gives nothing")
    func refusesMalformedDescriptions() {
        #expect(AccessoryBatteryReading.battery(from: description(type: "InternalBattery")) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(type: nil)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(type: 4)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(name: nil)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(name: "")) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(name: "   ")) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(name: 7)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(current: nil)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(maximum: nil)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(maximum: 0)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(maximum: -100)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(current: -1)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(current: true)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(maximum: false)) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(current: "90")) == nil)
        #expect(AccessoryBatteryReading.battery(from: description(maximum: "100")) == nil)
        #expect(AccessoryBatteryReading.battery(from: [:]) == nil)
    }

    @Test("The percentage is clamped to 0 to 100 and follows the ratio")
    func percentages() {
        #expect(AccessoryBatteryReading.battery(from: description(current: 120, maximum: 100))?.percent == 100)
        #expect(AccessoryBatteryReading.battery(from: description(current: 50, maximum: 200))?.percent == 25)
        #expect(AccessoryBatteryReading.battery(from: description(current: 0, maximum: 100))?.percent == 0)
        #expect(AccessoryBatteryReading.battery(from: description(current: 100_000, maximum: 1))?.percent == 100)
    }

    @Test("A low warning level outside 1 to 99 is dropped and the battery stays")
    func lowWarnLevelIsOptional() {
        #expect(AccessoryBatteryReading.battery(from: description(warn: 0))?.lowWarnLevel == nil)
        #expect(AccessoryBatteryReading.battery(from: description(warn: 100))?.lowWarnLevel == nil)
        #expect(AccessoryBatteryReading.battery(from: description(warn: -5))?.lowWarnLevel == nil)
        #expect(AccessoryBatteryReading.battery(from: description(warn: "20"))?.lowWarnLevel == nil)
        #expect(AccessoryBatteryReading.battery(from: description(warn: true))?.lowWarnLevel == nil)
        #expect(AccessoryBatteryReading.battery(from: description(warn: nil))?.lowWarnLevel == nil)
        #expect(AccessoryBatteryReading.battery(from: description(warn: 1))?.lowWarnLevel == 1)
        #expect(AccessoryBatteryReading.battery(from: description(warn: 99))?.lowWarnLevel == 99)
        #expect(AccessoryBatteryReading.battery(from: description(warn: 0)) != nil)
    }

    @Test("Without an identifier the id is built from the name")
    func idFallsBackToTheName() {
        #expect(AccessoryBatteryReading.battery(from: description(identifier: nil))?.id == "name:Magic Mouse")
        #expect(AccessoryBatteryReading.battery(from: description(identifier: ""))?.id == "name:Magic Mouse")
        #expect(AccessoryBatteryReading.battery(from: description(identifier: 42))?.id == "name:Magic Mouse")
    }

    @Test("A missing or odd category is nil, not a reason to drop the battery")
    func categoryIsOptional() {
        #expect(AccessoryBatteryReading.battery(from: description(category: nil))?.category == nil)
        #expect(AccessoryBatteryReading.battery(from: description(category: ""))?.category == nil)
        #expect(AccessoryBatteryReading.battery(from: description(category: 3))?.category == nil)
        #expect(AccessoryBatteryReading.battery(from: description(category: "Headset"))?.category == "Headset")
    }

    @Test("A name is trimmed and cut to 80 bytes without splitting a character")
    func namesAreTrimmedAndCut() {
        #expect(AccessoryBatteryReading.battery(from: description(name: "  Keys \n"))?.name == "Keys")
        let long = String(repeating: "a", count: 200)
        #expect(AccessoryBatteryReading.battery(from: description(name: long))?.name.utf8.count == 80)
        // 79 ASCII bytes then a two-byte character: the character would end at byte 81.
        let split = String(repeating: "a", count: 79) + "\u{00E9}" + "tail"
        let cut = AccessoryBatteryReading.battery(from: description(name: split))?.name
        #expect(cut == String(repeating: "a", count: 79))
        let emoji = String(repeating: "\u{1F3A7}", count: 30)
        let emojiCut = AccessoryBatteryReading.battery(from: description(name: emoji))?.name
        #expect(emojiCut?.utf8.count == 80)
        #expect(emojiCut?.unicodeScalars.count == 20)
    }

    @Test("A list skips invalid entries, keeps the first of equal ids, sorts and is capped at 20")
    func listing() {
        let first = description(name: "Zed", identifier: "id-1")
        let duplicate = description(name: "Other", identifier: "id-1")
        let second = description(name: "Alpha", identifier: "id-2")
        let invalid = description(name: nil, identifier: "id-3")
        let sameName = description(name: "Alpha", identifier: "id-0")
        let result = AccessoryBatteryReading.batteries(from: [first, duplicate, second, invalid, sameName])
        #expect(result.map(\.id) == ["id-0", "id-2", "id-1"])
        #expect(result.map(\.name) == ["Alpha", "Alpha", "Zed"])

        let many = (0..<30).map { description(name: "Device \($0)", identifier: "id-\($0)") }
        #expect(AccessoryBatteryReading.batteries(from: many).count == 20)
        #expect(AccessoryBatteryReading.batteries(from: []).isEmpty)
    }
}
