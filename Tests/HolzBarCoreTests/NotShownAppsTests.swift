import Foundation
import Testing
@testable import HolzBarCore

@Suite("NotShownApps")
struct NotShownAppsTests {
    private func source(
        _ id: String,
        name: String? = nil,
        fallback: String = "Fallback",
        path: String? = nil,
        reason: NotShownApps.Reason = .notInApplications
    ) -> NotShownApps.Source {
        NotShownApps.Source(id: id, name: name, fallbackName: fallback, path: path, reason: reason)
    }

    @Test("There are exactly three reasons, and none is about Accessibility")
    func threeReasons() {
        #expect(NotShownApps.Reason.allCases.count == 3)
        #expect(NotShownApps.Reason.allCases.map(\.rawValue) == [0, 1, 2])
    }

    @Test("An application the install location rule names is not in Applications; one only confirmed may be off in Settings")
    func reasonMapping() {
        #expect(NotShownApps.reason(unnameableByRule: true) == .notInApplications)
        #expect(NotShownApps.reason(unnameableByRule: false) == .mayBeOffInSettings)
    }

    @Test("The first two reasons are fixed in Finder, the third in System Settings")
    func fixes() {
        #expect(NotShownApps.fix(for: .notInApplications) == .showInFinder)
        #expect(NotShownApps.fix(for: .noAppIdentifier) == .showInFinder)
        #expect(NotShownApps.fix(for: .mayBeOffInSettings) == .openMenuBarSettings)
    }

    @Test("The Menu Bar pane link is the fixed System Settings URL")
    func settingsURL() {
        #expect(NotShownApps.menuBarSettingsURL == "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
        #expect(URL(string: NotShownApps.menuBarSettingsURL) != nil)
    }

    @Test("No sources give no rows")
    func empty() {
        #expect(NotShownApps.rows([]).isEmpty)
    }

    @Test("Rows are ordered by reason, then by name ignoring case")
    func order() {
        let rows = NotShownApps.rows([
            source("c", name: "zeta", reason: .mayBeOffInSettings),
            source("b", name: "beta", reason: .noAppIdentifier),
            source("a2", name: "Beta", reason: .notInApplications),
            source("a1", name: "alpha", reason: .notInApplications),
            source("a3", name: "Gamma", reason: .notInApplications),
        ])
        #expect(rows.map(\.id) == ["a1", "a2", "a3", "b", "c"])
    }

    @Test("One row per application: the first source wins")
    func oneRowPerID() {
        let rows = NotShownApps.rows([
            source("x", name: "First", reason: .notInApplications),
            source("x", name: "Second", reason: .mayBeOffInSettings),
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.name == "First")
        #expect(rows.first?.reason == .notInApplications)
        #expect(rows.first?.fix == .showInFinder)
    }

    @Test("A name another app chose is cleaned: bidi overrides and line breaks go")
    func cleanedNames() {
        let rows = NotShownApps.rows([source("a", name: "Evil\u{202E}App\nName ")])
        #expect(rows.first?.name == "EvilAppName")
    }

    @Test("A missing or empty name falls back to the bundle or executable name")
    func fallbackName() {
        let rows = NotShownApps.rows([
            source("a", name: nil, fallback: "tool"),
            source("b", name: "  ", fallback: "agent"),
        ])
        #expect(rows.map(\.name) == ["agent", "tool"])
    }

    @Test("A row keeps the path its fix reveals")
    func pathKept() {
        let rows = NotShownApps.rows([source("a", name: "A", path: "/opt/A.app")])
        #expect(rows.first?.path == "/opt/A.app")
    }
}
