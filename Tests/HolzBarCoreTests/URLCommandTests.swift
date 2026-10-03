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

    @Test("Zen mode takes on, off and toggle")
    func zenModeRequests() {
        #expect(action("holzbar://zen") == .zenMode(.toggle))
        #expect(action("holzbar://zen/toggle") == .zenMode(.toggle))
        #expect(action("holzbar://zen/on") == .zenMode(.turnOn))
        #expect(action("holzbar://zen/OFF") == .zenMode(.turnOff))
        #expect(action("holzbar://zen/whatever") == .zenMode(.toggle))
    }

    /// Every action, with a sample argument.
    private let allActions: [URLCommand.Action] = [
        .toggle(.hidden),
        .show(.alwaysHidden),
        .hide(.hidden),
        .search,
        .settings,
        .toggleShelf,
        .toggleAutoRehide,
        .toggleApplicationMenus,
        .zenMode(.turnOn),
        .zenMode(.turnOff),
        .zenMode(.toggle),
        .applyProfile("Work"),
        .unknown,
    ]

    @Test("Without Zen mode, only lasting changes ask first")
    func withoutZenModeLastingChangesAsk() {
        let off = ZenMode()
        let asking: [URLCommand.Action] = [.applyProfile("Work"), .toggleShelf, .toggleAutoRehide]
        for action in allActions {
            let expected: URLCommand.Decision = asking.contains(action) ? .ask : .perform
            #expect(action.decision(zenMode: off) == expected)
        }
    }

    @Test("Zen mode refuses lasting changes from other apps")
    func zenModeRefusesLastingChanges() {
        for zen in [ZenMode(isManual: true), ZenMode(isAutomatic: true)] {
            #expect(URLCommand.Action.applyProfile("Work").decision(zenMode: zen) == .refuse)
            #expect(URLCommand.Action.toggleShelf.decision(zenMode: zen) == .refuse)
            #expect(URLCommand.Action.toggleAutoRehide.decision(zenMode: zen) == .refuse)
            // Hiding stays possible; showing is refused where the section is known.
            #expect(URLCommand.Action.hide(.hidden).decision(zenMode: zen) == .perform)
        }
    }

    @Test("Another app may turn Zen mode on without asking")
    func zenModeTurnsOnWithoutAsking() {
        let states = [ZenMode(), ZenMode(isManual: true), ZenMode(isAutomatic: true), ZenMode(isManual: true, isAutomatic: true)]
        for zen in states {
            #expect(URLCommand.Action.zenMode(.turnOn).decision(zenMode: zen) == .perform)
        }
        #expect(URLCommand.Action.zenMode(.toggle).decision(zenMode: ZenMode()) == .perform)
        #expect(URLCommand.Action.zenMode(.turnOff).decision(zenMode: ZenMode()) == .perform)
    }

    @Test("Turning the user's Zen mode off asks first")
    func turningManualZenModeOffAsks() {
        let manual = ZenMode(isManual: true)
        #expect(URLCommand.Action.zenMode(.turnOff).decision(zenMode: manual) == .ask)
        #expect(URLCommand.Action.zenMode(.toggle).decision(zenMode: manual) == .ask)
    }

    @Test("Zen mode during a screen share cannot be turned off by another app")
    func automaticZenModeCannotBeTurnedOff() {
        for zen in [ZenMode(isAutomatic: true), ZenMode(isManual: true, isAutomatic: true)] {
            #expect(URLCommand.Action.zenMode(.turnOff).decision(zenMode: zen) == .refuse)
            #expect(URLCommand.Action.zenMode(.toggle).decision(zenMode: zen) == .refuse)
        }
    }
}
