import Foundation
import Testing
@testable import HolzBarCore

@Suite("Acknowledgements")
struct AcknowledgementsTests {
    private struct Resolved: Decodable {
        struct Pin: Decodable {
            struct State: Decodable {
                let version: String?
            }

            let location: String
            let state: State
        }

        let pins: [Pin]
    }

    /// The root of the repository, three levels above this file.
    private static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let packageResolvedURL = repositoryRoot
        .appending(path: "holzBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")

    private static let licenseDirectory = repositoryRoot
        .appending(path: "holzBar/Resources/Acknowledgements")

    /// A repository URL, lowercased and without a trailing ".git" or "/".
    private static func normalized(_ location: String) -> String {
        var location = location.lowercased()
        while location.hasSuffix("/") {
            location.removeLast()
        }
        if location.hasSuffix(".git") {
            location.removeLast(4)
        }
        while location.hasSuffix("/") {
            location.removeLast()
        }
        return location
    }

    /// The pins of `Package.resolved`; none when the file is missing (no package is linked).
    private static func resolvedPins() throws -> [Resolved.Pin] {
        guard FileManager.default.fileExists(atPath: packageResolvedURL.path(percentEncoded: false)) else {
            return []
        }
        let data = try Data(contentsOf: packageResolvedURL)
        return try JSONDecoder().decode(Resolved.self, from: data).pins
    }

    @Test("The acknowledgements list exactly the resolved packages")
    func listsExactlyTheResolvedPackages() throws {
        let pins = try Self.resolvedPins()

        let pinVersions = Dictionary(
            pins.map { (Self.normalized($0.location), $0.state.version) },
            uniquingKeysWith: { first, _ in first }
        )
        let packageVersions = Dictionary(
            Acknowledgements.packages.map { (Self.normalized($0.repository), $0.version) },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(Set(packageVersions.keys) == Set(pinVersions.keys))
        #expect(Acknowledgements.packages.count == pins.count)
        for (repository, version) in packageVersions {
            #expect(version != nil, "\(repository) has no version")
            #expect(version == pinVersions[repository] ?? nil, "\(repository) differs from Package.resolved")
        }
    }

    @Test("Every package has its license text")
    func everyPackageHasItsLicenseText() throws {
        for package in Acknowledgements.packages {
            let file = try #require(package.licenseFile, "\(package.name) has no license file")
            let url = Self.licenseDirectory.appending(path: file).appendingPathExtension("txt")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.isEmpty, "\(file).txt is empty")
            #expect(text.contains("Copyright"), "\(file).txt has no copyright notice")
        }
    }

    @Test("Every license file belongs to a package")
    func everyLicenseFileBelongsToAPackage() throws {
        // A missing license folder means there are no license files.
        let files: [String]
        if FileManager.default.fileExists(atPath: Self.licenseDirectory.path(percentEncoded: false)) {
            files = try FileManager.default.contentsOfDirectory(atPath: Self.licenseDirectory.path(percentEncoded: false))
                .filter { $0.hasSuffix(".txt") }
        } else {
            files = []
        }
        let expected = Acknowledgements.packages.compactMap(\.licenseFile).map { "\($0).txt" }
        #expect(Set(files) == Set(expected))
        #expect(files.count == expected.count)
    }

    @Test("Sparkle is not acknowledged")
    func sparkleIsNotAcknowledged() {
        for acknowledgement in Acknowledgements.adaptedCode + Acknowledgements.packages {
            let fields = [acknowledgement.name, acknowledgement.repository, acknowledgement.licenseFile ?? ""]
            for field in fields {
                #expect(!field.lowercased().contains("sparkle"), "\(acknowledgement.name) mentions Sparkle")
            }
        }
    }

    @Test("The adapted code is credited")
    func adaptedCodeIsCredited() {
        let adapted = Acknowledgements.adaptedCode
        #expect(adapted.map(\.name) == ["Ice", "Barometer", "Thaw"])
        #expect(adapted.map(\.repository) == [
            "https://github.com/jordanbaird/Ice",
            "https://github.com/mackid1993/Barometer",
            "https://github.com/thaw-app/Thaw",
        ])
        for acknowledgement in adapted {
            #expect(acknowledgement.license == "GNU General Public License v3.0")
            #expect(acknowledgement.version == nil)
            #expect(acknowledgement.licenseFile == nil)
        }
    }
}
