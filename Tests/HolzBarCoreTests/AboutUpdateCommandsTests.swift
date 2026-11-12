import Testing
@testable import HolzBarCore

@Suite("AboutUpdateCommands")
struct AboutUpdateCommandsTests {
    @Test("The two commands update the stable and the beta cask")
    func commandTexts() {
        #expect(AboutUpdateCommands.stable == .init(channel: .stable, text: "brew update && brew upgrade --cask holzbar"))
        #expect(AboutUpdateCommands.beta == .init(channel: .beta, text: "brew update && brew upgrade --cask holzbar@beta"))
    }

    @Test("A pre-release shows the beta command first")
    func orderByPrerelease() {
        #expect(AboutUpdateCommands.commands(isPrerelease: false) == [AboutUpdateCommands.stable, AboutUpdateCommands.beta])
        #expect(AboutUpdateCommands.commands(isPrerelease: true) == [AboutUpdateCommands.beta, AboutUpdateCommands.stable])
    }

    @Test("The running version decides the order", arguments: [
        ("1.1.0", AboutUpdateCommands.Channel.stable),
        ("1.1.0-beta1", .beta),
        ("1.0.5-alpha2", .beta),
        ("not a version", .stable),
        ("", .stable),
    ])
    func orderByVersion(version: String, first: AboutUpdateCommands.Channel) {
        #expect(AboutUpdateCommands.commands(forVersion: version).first?.channel == first)
    }

    @Test("Every result holds both commands once, each with brew update first")
    func everyResultIsComplete() {
        for version in ["1.1.0", "1.1.0-beta1", ""] {
            let commands = AboutUpdateCommands.commands(forVersion: version)
            #expect(commands.count == 2)
            #expect(Set(commands.map(\.text)).count == 2)
            for command in commands {
                #expect(command.text.hasPrefix("brew update && brew upgrade --cask "))
            }
        }
    }
}
