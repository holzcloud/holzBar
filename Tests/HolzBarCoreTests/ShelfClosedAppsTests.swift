//
//  ShelfClosedAppsTests.swift
//  holzBar
//

import Foundation
import Testing

@testable import HolzBarCore

@Suite("Closed applications in the holzBar Shelf")
struct ShelfClosedAppsTests {
    private let own = "com.holzcloud.holzBar"

    private func result(
        macOS27: Bool,
        layout: [String: Int] = [:],
        sections: [String: Int] = [:],
        running: Set<String> = []
    ) -> (hidden: [String], alwaysHidden: [String]) {
        ShelfClosedApps.bundleIdentifiers(
            usesMacOS27Layout: macOS27,
            macOS27Layout: layout,
            itemSections: sections,
            running: running,
            ownBundleIdentifier: own
        )
    }

    @Test("On macOS 27 the applications of the saved layout that are not running are listed")
    func macOS27() {
        let found = result(
            macOS27: true,
            layout: ["org.example.B": 1, "org.example.A": 2, "org.example.Seen": 0, "org.example.Up": 1],
            running: ["org.example.Up"]
        )
        #expect(found.hidden == ["org.example.B"])
        #expect(found.alwaysHidden == ["org.example.A"])
    }

    @Test("Before macOS 27 the bundle identifier is the start of the item key")
    func beforeMacOS27() {
        let found = result(
            macOS27: false,
            // The layout of macOS 27 is not read before it.
            layout: ["org.example.C": 1],
            sections: ["org.example.A:Item-0": 1, "org.example.A:Item-1": 1, "org.example.B:Status": 2]
        )
        #expect(found.hidden == ["org.example.A"])
        #expect(found.alwaysHidden == ["org.example.B"])
    }

    @Test("An application with a visible item is not listed, and one in two sections takes the more visible")
    func mostVisible() {
        let found = result(
            macOS27: false,
            sections: ["org.example.A:one": 0, "org.example.A:two": 2, "org.example.B:one": 2, "org.example.B:two": 1]
        )
        #expect(found.hidden == ["org.example.B"])
        #expect(found.alwaysHidden.isEmpty)
    }

    @Test("Running applications are left out whatever the case of their identifier")
    func running() {
        let found = result(macOS27: true, layout: ["org.example.Mixed": 1], running: ["ORG.EXAMPLE.MIXED"])
        #expect(found.hidden.isEmpty)
    }

    @Test("The system, holzBar and names that are no application are left out")
    func excluded() {
        let found = result(
            macOS27: false,
            sections: [
                "com.apple.controlcenter:Clock": 1,
                "com.holzcloud.holzBar:Item": 1,
                "6F1A5C1E-5B0F-4E0B-9DB5-6A2C2C0C1D6E:Item": 1,
                "nodot:Item": 1,
                "org.example.Real:Item": 1,
            ]
        )
        #expect(found.hidden == ["org.example.Real"])
    }

    @Test("A section index nothing uses is ignored")
    func unknownSection() {
        let found = result(macOS27: true, layout: ["org.example.A": 7, "org.example.B": -1])
        #expect(found.hidden.isEmpty)
        #expect(found.alwaysHidden.isEmpty)
    }

    @Test("The list for a section is limited, and sorted")
    func limited() {
        var layout = [String: Int]()
        for number in 0..<(ShelfClosedApps.maximumPerSection + 5) {
            layout["org.example.App\(String(format: "%02d", number))"] = 1
        }
        let found = result(macOS27: true, layout: layout)
        #expect(found.hidden.count == ShelfClosedApps.maximumPerSection)
        #expect(found.hidden == found.hidden.sorted())
        #expect(found.hidden.first == "org.example.App00")
    }
}
