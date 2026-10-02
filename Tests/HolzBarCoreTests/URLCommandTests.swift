import Foundation
import Testing
@testable import HolzBarCore

@Suite("URLCommand")
struct URLCommandTests {
    /// The command in `string`, or `nil` when it is none (or not even a URL).
    private func parse(_ string: String) -> URLCommand? {
        guard let url = URL(string: string) else {
            return nil
        }
        return URLCommand(url: url, scheme: "holzbar")
    }

    @Test("A command and its argument are read")
    func commandAndArgument() throws {
        let command = try #require(parse("holzbar://toggle/always-hidden"))
        #expect(command.name == "toggle")
        #expect(command.arguments == ["always-hidden"])
    }

    @Test("Profile names keep their case and spaces")
    func profileNameKeepsCaseAndSpaces() throws {
        let command = try #require(parse("holzbar://profile/My%20Work"))
        #expect(command.name == "profile")
        #expect(command.arguments == ["My Work"])
    }

    @Test("The command is case-insensitive")
    func commandIsCaseInsensitive() throws {
        let command = try #require(parse("HOLZBAR://Toggle/Hidden"))
        #expect(command.name == "toggle")
        #expect(command.arguments == ["Hidden"])
    }

    @Test("Another scheme is not a command")
    func anotherScheme() {
        #expect(parse("https://holzcloud.ch/toggle") == nil)
    }

    @Test("A URL without a command is ignored")
    func urlWithoutCommand() {
        #expect(parse("holzbar:") == nil)
        #expect(parse("holzbar:///") == nil)
    }

    @Test("A command without arguments has none")
    func commandWithoutArguments() throws {
        let command = try #require(parse("holzbar://settings"))
        #expect(command.name == "settings")
        #expect(command.arguments.isEmpty)
    }
}
