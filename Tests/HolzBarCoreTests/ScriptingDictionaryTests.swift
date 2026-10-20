//
//  ScriptingDictionaryTests.swift
//  holzBar
//

import Foundation
import Testing

/// The AppleScript dictionary is a small, read-mostly door (T-13-H1): these tests fail when a
/// command or a writable property is added without a decision.
@Suite("The AppleScript dictionary")
struct ScriptingDictionaryTests {
    private final class Collector: NSObject, XMLParserDelegate {
        var commands = [String]()
        var classes = [String]()
        var propertyAccess = [String: String]()

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = attributeDict["name"] ?? ""
            switch elementName {
            case "command": commands.append(name)
            case "class": classes.append(name)
            case "property": propertyAccess[name] = attributeDict["access"] ?? "rw"
            default: break
            }
        }
    }

    private func parse() throws -> Collector {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "holzBar/Resources/holzBar.sdef")
        let parser = XMLParser(data: try Data(contentsOf: url))
        let collector = Collector()
        parser.delegate = collector
        #expect(parser.parse())
        return collector
    }

    @Test("It lists exactly the allowed commands")
    func commands() throws {
        let collector = try parse()
        #expect(collector.commands.sorted() == [
            "apply profile", "disable rule", "disable zen mode", "enable rule", "enable zen mode",
            "hide section", "show section", "toggle section",
        ])
    }

    @Test("It has only the application class, and every property is read only")
    func readOnly() throws {
        let collector = try parse()
        #expect(collector.classes == ["application"])
        #expect(collector.propertyAccess.count == 6)
        #expect(collector.propertyAccess.values.allSatisfy { $0 == "r" })
    }
}
