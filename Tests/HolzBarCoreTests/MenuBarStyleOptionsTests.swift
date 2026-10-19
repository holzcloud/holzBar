import Foundation
import Testing
@testable import HolzBarCore

@Suite("MenuBarStyleOptions")
struct MenuBarStyleOptionsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("Stored raw values never change")
    func storedRawValuesNeverChange() {
        #expect(MenuBarAppleLogoStyle.allCases.map(\.rawValue) == [0, 1])
        #expect(MenuBarAppleLogoFill.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(MenuBarBorderFill.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(MenuBarGradientDirection.allCases.map(\.rawValue) == [0, 1])
        #expect(MenuBarGradientSpan.allCases.map(\.rawValue) == [0, 1])
    }

    @Test("An unknown raw value decodes to the first case of each enum")
    func unknownRawValueFallsBackToTheFirstCase() throws {
        #expect(try decode(MenuBarAppleLogoStyle.self, "7") == .standard)
        #expect(try decode(MenuBarAppleLogoFill.self, "7") == .barTint)
        #expect(try decode(MenuBarBorderFill.self, "7") == .color)
        #expect(try decode(MenuBarGradientDirection.self, "7") == .horizontal)
        #expect(try decode(MenuBarGradientSpan.self, "7") == .acrossBar)
    }

    @Test("An empty object decodes to the default, which draws what 0.0.8-beta3 drew")
    func emptyObjectDecodesToTheDefault() throws {
        let style = try decode(MenuBarPartialStyle.self, "{}")
        #expect(style == MenuBarPartialStyle.default)
        #expect(style.tintStrength == 0.2)
        #expect(style.gradientDirection == .horizontal)
        #expect(style.gradientSpan == .acrossBar)
        #expect(style.borderFill == .color)
        #expect(style.appleLogoFill == .barTint)
    }

    @Test("A damaged field falls back alone and keeps the others")
    func damagedFieldFallsBackAlone() throws {
        let style = try decode(MenuBarPartialStyle.self, #"{"tintStrength":"x","borderFill":2}"#)
        #expect(style.tintStrength == 0.2)
        #expect(style.borderFill == .gradient)
        let other = try decode(MenuBarPartialStyle.self, #"{"gradientDirection":[1],"appleLogoFill":3}"#)
        #expect(other.gradientDirection == .horizontal)
        #expect(other.appleLogoFill == .color)
    }

    @Test("The tint strength is kept in 0.1 to 0.6, and a value that is not finite gives 0.2")
    func tintStrengthIsClamped() throws {
        #expect(MenuBarPartialStyle.clampedTintStrength(0.95) == 0.6)
        #expect(MenuBarPartialStyle.clampedTintStrength(0.01) == 0.1)
        #expect(MenuBarPartialStyle.clampedTintStrength(0.35) == 0.35)
        #expect(MenuBarPartialStyle.clampedTintStrength(.nan) == 0.2)
        #expect(MenuBarPartialStyle.clampedTintStrength(.infinity) == 0.2)
        #expect(try decode(MenuBarPartialStyle.self, #"{"tintStrength":0.95}"#).tintStrength == 0.6)
        #expect(try decode(MenuBarPartialStyle.self, #"{"tintStrength":0.01}"#).tintStrength == 0.1)
    }

    @Test("The default encodes to exactly its five keys and decodes back to itself")
    func defaultRoundTripsWithItsKeyNames() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(MenuBarPartialStyle.default)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.sorted() == ["appleLogoFill", "borderFill", "gradientDirection", "gradientSpan", "tintStrength"])
        #expect(try JSONDecoder().decode(MenuBarPartialStyle.self, from: data) == .default)
    }

    @Test("A changed style round-trips")
    func changedStyleRoundTrips() throws {
        let style = MenuBarPartialStyle(
            tintStrength: 0.45,
            gradientDirection: .vertical,
            gradientSpan: .eachShape,
            borderFill: .accentColor,
            appleLogoFill: .wallpaper
        )
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(MenuBarPartialStyle.self, from: data) == style)
    }

    @Test("The gradient direction gives the angle the overlay draws with")
    func gradientDirectionAngles() {
        #expect(MenuBarGradientDirection.horizontal.angle == 0)
        #expect(MenuBarGradientDirection.vertical.angle == 270)
    }

    @Test("The default tint strength is the alpha every tint used so far")
    func defaultTintStrengthIsTwentyPercent() {
        #expect(MenuBarPartialStyle.defaultTintStrength == 0.2)
        #expect(MenuBarPartialStyle.tintStrengthRange == 0.1...0.6)
    }
}
