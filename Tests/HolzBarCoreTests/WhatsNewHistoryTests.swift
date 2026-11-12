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
        #expect(Self.releases.first?.version == "1.1.0")
    }

    @Test("1.0.5 lists the hiding fixes as grouped lines next to its improvement")
    func release105ListsTheHidingFixes() throws {
        let release = try #require(Self.releases.first { $0.version == "1.0.5" })
        #expect(release.improved.count == 1)
        #expect(release.fixed.count >= 8, "1.0.5 should list the grouped hiding fixes")
        #expect(release.fixed.count <= 12, "the hiding fixes should stay grouped into about ten lines")
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
        let tabs = WhatsNewPolicy.tabs(knownVersions: versions, current: "1.1.0-beta1")
        #expect(tabs.versions == versions)
        #expect(tabs.installed == "1.1.0")
    }

    // MARK: String Catalog

    /// The repository root, three levels above this file. The link is resolved because the
    /// Linux script symlinks the test into a throwaway package.
    private static let repositoryRoot = URL(filePath: #filePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Registry: Decodable {
        struct Language: Decodable {
            let code: String
        }

        let source: String
        let languages: [Language]
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable {
                    let state: String?
                    let value: String?
                }

                let stringUnit: StringUnit?
            }

            let localizations: [String: Localization]?
        }

        let strings: [String: Entry]
    }

    @Test("Every text of the history is a catalog key translated into every language")
    func textsAreTranslated() throws {
        let registry = try JSONDecoder().decode(
            Registry.self,
            from: Data(contentsOf: Self.repositoryRoot.appending(path: "Translations/languages.json"))
        )
        let targets = registry.languages.map(\.code).filter { $0 != registry.source }
        #expect(!targets.isEmpty)
        let catalog = try JSONDecoder().decode(
            Catalog.self,
            from: Data(contentsOf: Self.repositoryRoot.appending(path: "holzBar/Resources/Localizable.xcstrings"))
        )
        for text in Set(Self.allTexts) {
            guard let entry = catalog.strings[text] else {
                Issue.record("Localizable.xcstrings has no key \"\(text)\"")
                continue
            }
            for code in targets {
                let unit = entry.localizations?[code]?.stringUnit
                let translated = unit?.state == "translated" && !(unit?.value ?? "").isEmpty
                #expect(translated, "\"\(text)\" has no finished translation in \(code)")
            }
        }
    }
}
