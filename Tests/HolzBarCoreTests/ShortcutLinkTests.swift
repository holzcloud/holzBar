import Foundation
import Testing
@testable import HolzBarCore

@Suite("ShortcutLink")
struct ShortcutLinkTests {
    /// The characters that stay unencoded in the query value (RFC 3986 unreserved), and `%`.
    private static let allowedInValue = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%")

    private func queryItems(of url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    // MARK: The URL

    @Test("A name stays one query value, whatever it holds")
    func nameStaysOneValue() throws {
        let names = [
            "Morning & Evening", "a=b", "#1", "100%", "a+b", "what?", "Süß", "🚀 Launch",
            "x&name=other", "a b", "a;b", "a/b", "'quoted'", "100% & 50% = ?#+",
        ]
        for name in names {
            let url = try #require(ShortcutLink.runURL(forShortcutNamed: name), "name \(name)")
            #expect(url.scheme == "shortcuts")
            #expect(url.host == "run-shortcut")
            let items = queryItems(of: url)
            #expect(items.count == 1, "name \(name)")
            #expect(items.first?.name == "name")
            #expect(items.first?.value == name, "name \(name)")

            // Nothing but unreserved characters and percent escapes follows `name=`.
            let text = url.absoluteString
            let prefix = "shortcuts://run-shortcut?name="
            #expect(text.hasPrefix(prefix))
            let value = text.dropFirst(prefix.count)
            #expect(value.allSatisfy { Self.allowedInValue.contains($0) }, "name \(name)")
        }
    }

    @Test("The URL is exactly the scheme, the host and one encoded name")
    func exactURL() {
        #expect(ShortcutLink.runURL(forShortcutNamed: "Morning")?.absoluteString == "shortcuts://run-shortcut?name=Morning")
        #expect(ShortcutLink.runURL(forShortcutNamed: "A B")?.absoluteString == "shortcuts://run-shortcut?name=A%20B")
        #expect(ShortcutLink.runURL(forShortcutNamed: "a+b")?.absoluteString == "shortcuts://run-shortcut?name=a%2Bb")
        #expect(ShortcutLink.runURL(forShortcutNamed: "a&b=c")?.absoluteString == "shortcuts://run-shortcut?name=a%26b%3Dc")
        #expect(ShortcutLink.runURL(forShortcutNamed: "ä")?.absoluteString == "shortcuts://run-shortcut?name=%C3%A4")
        #expect(ShortcutLink.runURL(forShortcutNamed: "a-b_c.d~e")?.absoluteString == "shortcuts://run-shortcut?name=a-b_c.d~e")
    }

    @Test("The URL asks for nothing back")
    func noCallback() throws {
        let url = try #require(ShortcutLink.runURL(forShortcutNamed: "Morning"))
        let text = url.absoluteString.lowercased()
        #expect(!text.contains("callback"))
        #expect(!text.contains("x-success"))
        #expect(!text.contains("x-error"))
        #expect(!text.contains("input"))
        #expect(queryItems(of: url).map(\.name) == ["name"])
    }

    @Test("A padded name gives the same URL as the plain one")
    func paddedNameGivesSameURL() {
        let plain = ShortcutLink.runURL(forShortcutNamed: "Morning")
        #expect(plain != nil)
        #expect(ShortcutLink.runURL(forShortcutNamed: "  Morning \n") == plain)
    }

    // MARK: The name

    @Test("Names are kept as typed, trimmed")
    func ordinaryNamesAreKept() {
        for name in ["Morning Routine", "Wäsche starten", "日本語のショートカット", "😀 Go", "It's 5 o'clock", "a/b.c-d"] {
            #expect(ShortcutLink.cleanedName(name) == name)
        }
        #expect(ShortcutLink.cleanedName("  Morning \n") == "Morning")
        #expect(ShortcutLink.cleanedName("\u{00A0}Morning\u{00A0}") == "Morning")
    }

    @Test("An empty or blank name is refused")
    func emptyNameIsRefused() {
        for name in ["", " ", "   ", "\n", "\t \n"] {
            #expect(ShortcutLink.cleanedName(name) == nil)
            #expect(ShortcutLink.runURL(forShortcutNamed: name) == nil)
        }
    }

    @Test("A name over 255 bytes is refused")
    func longNameIsRefused() {
        #expect(ShortcutLink.maximumNameBytes == 255)
        #expect(ShortcutLink.cleanedName(String(repeating: "a", count: 255)) != nil)
        #expect(ShortcutLink.cleanedName(String(repeating: "a", count: 256)) == nil)
        // The limit counts bytes, not characters: 127 umlauts are 254 bytes, 128 are 256.
        #expect(ShortcutLink.cleanedName(String(repeating: "ä", count: 127)) != nil)
        #expect(ShortcutLink.cleanedName(String(repeating: "ä", count: 128)) == nil)
        #expect(ShortcutLink.runURL(forShortcutNamed: String(repeating: "a", count: 256)) == nil)
    }

    @Test("Control, format, bidirectional and other deceptive characters are refused")
    func deceptiveCharactersAreRefused() {
        let scalars: [UInt32] = [
            0x0000, 0x0007, 0x001B, 0x007F, 0x0085, // control
            0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD, // zero width, joiner, word joiner, BOM, soft hyphen
            0x200E, 0x200F, 0x061C, // direction marks
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // embeddings and overrides
            0x2066, 0x2067, 0x2068, 0x2069, // isolates
            0x2028, 0x2029, // line and paragraph separator
            0xE000, 0xF8FF, // private use
            0x0378, 0xFFFF, // unassigned
        ]
        for value in scalars {
            guard let scalar = Unicode.Scalar(value) else {
                Issue.record("not a scalar: \(value)")
                continue
            }
            let inside = "a\(Character(scalar))b"
            #expect(ShortcutLink.cleanedName(inside) == nil, "U+\(String(value, radix: 16)) inside")
            let leading = "\(Character(scalar))Morning"
            #expect(ShortcutLink.cleanedName(leading) == nil, "U+\(String(value, radix: 16)) leading")
            let trailing = "Morning\(Character(scalar))"
            #expect(ShortcutLink.cleanedName(trailing) == nil, "U+\(String(value, radix: 16)) trailing")
            #expect(ShortcutLink.runURL(forShortcutNamed: inside) == nil)
        }
        // A line break inside a name is a control character; at the ends it is only trimmed.
        #expect(ShortcutLink.cleanedName("Morning\nEvening") == nil)
        #expect(ShortcutLink.cleanedName("Morning\tEvening") == nil)
    }

    // MARK: The stored names

    @Test("Stored names keep only widgets that exist, with valid names")
    func storedNamesKeepExistingWidgets() {
        let kept = UUID()
        let trimmed = UUID()
        let invalid = UUID()
        let notString = UUID()
        let unknown = UUID()
        let stored: [String: Any] = [
            kept.uuidString: "Morning",
            trimmed.uuidString: "  Evening  ",
            invalid.uuidString: "bad\u{202E}name",
            notString.uuidString: 5,
            unknown.uuidString: "Other",
            "not-a-uuid": "Morning",
            "": "Morning",
        ]
        let names = ShortcutLink.storedNames(stored, keeping: [kept, trimmed, invalid, notString])
        #expect(names == [kept: "Morning", trimmed: "Evening"])
    }

    @Test("Nothing stored gives no names")
    func nothingStored() {
        #expect(ShortcutLink.storedNames(nil, keeping: [UUID()]).isEmpty)
        #expect(ShortcutLink.storedNames([:], keeping: [UUID()]).isEmpty)
        #expect(ShortcutLink.storedNames([UUID().uuidString: "Morning"], keeping: []).isEmpty)
    }

    @Test("At most as many names as there are widgets")
    func storedNamesAreCapped() {
        let ids = (0..<10).map { _ in UUID() }
        var stored: [String: Any] = [:]
        for id in ids {
            stored[id.uuidString] = "Shortcut"
        }
        let names = ShortcutLink.storedNames(stored, keeping: Set(ids))
        #expect(names.count == WidgetDefinition.maximumCount)
        // The same ones every time.
        #expect(names == ShortcutLink.storedNames(stored, keeping: Set(ids)))
    }
}
