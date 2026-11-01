import Foundation
import Testing
@testable import HolzBarCore

@Suite("WhatsNewHistory")
struct WhatsNewHistoryTests {
    private static let releases = WhatsNewHistory.releases

    /// Every text the history shows, as it appears on screen: the English catalog keys.
    private static var allTexts: [String] {
        releases.flatMap { release in
            (release.new + release.improved).flatMap { [$0.title, $0.detail] } + release.fixed.map(\.text)
        }
    }

    @Test("Versions are parseable, unique and strictly newest first")
    func versionsAreOrdered() throws {
        #expect(!Self.releases.isEmpty)
        let parsed = try Self.releases.map { release in
            try #require(AppVersion(release.version), "\(release.version) does not parse")
        }
        for (older, newer) in zip(parsed.dropFirst(), parsed) {
            #expect(older < newer, "the history is not strictly newest first")
        }
        #expect(Set(parsed.map(\.core)).count == parsed.count)
    }

    @Test("The history starts at 1.0.0 and the newest entry is the newest release")
    func historyBounds() {
        #expect(Self.releases.last?.version == "1.0.0")
        #expect(Self.releases.first?.version == "1.0.1")
    }

    @Test("Every release has content and every text is a plain one-line literal")
    func structureOfEntries() {
        for release in Self.releases {
            #expect(
                release.new.count + release.improved.count + release.fixed.count > 0,
                "\(release.version) has no entries"
            )
            for item in release.new + release.improved {
                #expect(!item.title.isEmpty && !item.detail.isEmpty)
                #expect(
                    item.symbol.range(of: "^[a-z0-9]+(\\.[a-z0-9]+)*$", options: .regularExpression) != nil,
                    "\(item.symbol) is not an SF Symbol name"
                )
            }
            for fix in release.fixed {
                #expect(!fix.text.isEmpty)
            }
        }
        for text in Self.allTexts {
            #expect(!text.contains("\\") && !text.contains("\"") && !text.contains("\n"), "\(text) is not a plain text")
            #expect(text == text.trimmingCharacters(in: .whitespaces), "\(text) has stray whitespace")
        }
    }

    @Test("The versions are plain core versions the policy can list")
    func versionsSuitThePolicy() {
        let versions = Self.releases.map(\.version)
        #expect(versions.allSatisfy { AppVersion($0)?.isPrerelease == false })
        let tabs = WhatsNewPolicy.tabs(knownVersions: versions, current: "1.0.1-beta1")
        #expect(tabs.versions == versions)
        #expect(tabs.installed == "1.0.1")
    }
}
