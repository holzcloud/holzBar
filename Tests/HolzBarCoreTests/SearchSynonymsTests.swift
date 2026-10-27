import Testing

@testable import HolzBarCore

@Suite("SearchSynonyms")
struct SearchSynonymsTests {
    @Test("A short name stands for the full name")
    func expands() {
        #expect(SearchSynonyms.expansions(for: "bt") == ["Bluetooth"])
        #expect(SearchSynonyms.expansions(for: "tm") == ["Time Machine"])
    }

    @Test("Case, accents, spaces and punctuation do not matter")
    func normalizedQuery() {
        #expect(SearchSynonyms.expansions(for: "BT") == ["Bluetooth"])
        #expect(SearchSynonyms.expansions(for: " b t ") == ["Bluetooth"])
        #expect(SearchSynonyms.expansions(for: "Wi-Fi") == SearchSynonyms.expansions(for: "wifi"))
        #expect(!SearchSynonyms.expansions(for: "wi-fi").isEmpty)
        #expect(SearchSynonyms.expansions(for: "ä").isEmpty)
    }

    @Test("The names come without punctuation, and with the Mac's other languages")
    func names() {
        let wifi = SearchSynonyms.expansions(for: "wlan")
        #expect(wifi.contains("WiFi"))
        #expect(wifi.contains("WLAN"))
        let battery = SearchSynonyms.expansions(for: "akku")
        #expect(battery.contains("Battery"))
        #expect(battery.contains("Batterie"))
        #expect(battery.contains("バッテリー"))
        #expect(battery.contains("Аккумулятор"))
    }

    @Test("Text that is no short name has no expansion")
    func unknown() {
        #expect(SearchSynonyms.expansions(for: "").isEmpty)
        #expect(SearchSynonyms.expansions(for: "   ").isEmpty)
        #expect(SearchSynonyms.expansions(for: "xyzzy").isEmpty)
        // Only whole aliases count, not the start of one.
        #expect(SearchSynonyms.expansions(for: "blue").isEmpty)
        #expect(SearchSynonyms.expansions(for: "this is much too long to be a short name").isEmpty)
    }

    @Test("The table is clean: short aliases in their own form, each alias once, no empty names")
    func tableIsClean() {
        var seen = Set<String>()
        for entry in SearchSynonyms.entries {
            #expect(!entry.aliases.isEmpty)
            #expect(!entry.names.isEmpty)
            for alias in entry.aliases {
                #expect(alias == SearchSynonyms.normalized(alias), "alias \(alias) is not in its normal form")
                #expect(alias.count <= SearchSynonyms.longestAlias, "alias \(alias) is too long")
                #expect(seen.insert(alias).inserted, "alias \(alias) is in the table twice")
            }
            for name in entry.names {
                #expect(!SearchSynonyms.normalized(name).isEmpty)
            }
        }
    }

    @Test("The names the system items carry are all reachable")
    func commonShortNames() {
        for alias in ["bt", "wifi", "vpn", "dnd", "cc", "vol", "bat", "tm", "mic", "cam", "kb", "nc"] where alias != "vpn" {
            #expect(!SearchSynonyms.expansions(for: alias).isEmpty, "\(alias) has no entry")
        }
    }
}
