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

    /// The action of the command in `string`, or `nil` when it is no command.
    private func action(_ string: String) -> URLCommand.Action? {
        parse(string)?.action
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

    @Test("Show and hide pick the section")
    func showAndHidePickSection() {
        #expect(action("holzbar://show/always-hidden") == .show(.alwaysHidden))
        #expect(action("holzbar://toggle/AlwaysHidden") == .toggle(.alwaysHidden))
        #expect(action("holzbar://hide") == .hide(.hidden))
        #expect(action("holzbar://show/hidden") == .show(.hidden))
    }

    @Test("The old Shelf command still works")
    func oldShelfCommandWorks() throws {
        let shelf = try #require(parse("holzbar://shelf/toggle"))
        let iceBar = try #require(parse("holzbar://ice-bar/toggle"))
        #expect(shelf.action == .toggleShelf)
        #expect(iceBar.action == shelf.action)
    }

    @Test("A profile needs a name")
    func profileNeedsName() {
        #expect(action("holzbar://profile") == .unknown)
        #expect(action("holzbar://profile/Work") == .applyProfile("Work"))
    }

    @Test("Unknown commands are recognised")
    func unknownCommands() {
        #expect(action("holzbar://launch-rockets") == .unknown)
    }

    @Test("Every other command maps to its action")
    func otherCommands() {
        #expect(action("holzbar://search") == .search)
        #expect(action("holzbar://settings") == .settings)
        #expect(action("holzbar://auto-rehide/toggle") == .toggleAutoRehide)
        #expect(action("holzbar://application-menus/toggle") == .toggleApplicationMenus)
    }

    @Test("Applying a profile asks first")
    func applyingAProfileAsksFirst() {
        #expect(URLCommand.Action.applyProfile("Work").needsConfirmation)
        let others: [URLCommand.Action] = [
            .toggle(.hidden),
            .show(.alwaysHidden),
            .hide(.hidden),
            .search,
            .settings,
            .toggleShelf,
            .toggleAutoRehide,
            .toggleApplicationMenus,
            .unknown,
        ]
        for other in others {
            #expect(!other.needsConfirmation)
        }
    }
}
