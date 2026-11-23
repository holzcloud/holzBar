import Foundation
import Testing
@testable import HolzBarCore

@Suite("AudioOutputList")
struct AudioOutputListTests {
    private func device(
        _ uid: String,
        name: String? = nil,
        channels: Int = 2,
        hidden: Bool = false,
        transport: AudioTransport = .builtIn
    ) -> AudioOutputDevice {
        AudioOutputDevice(uid: uid, name: name ?? uid, outputChannels: channels, isHidden: hidden, transport: transport)
    }

    @Test("Aggregate, virtual, hidden and output-less devices are not listed")
    func filters() {
        let devices = [
            device("speakers", name: "MacBook Pro Speakers"),
            device("pods", name: "AirPods", transport: .bluetooth),
            device("aggregate", name: "Aggregate", transport: .aggregate),
            device("loopback", name: "Loopback", transport: .virtual),
            device("hidden", name: "Hidden", hidden: true),
            device("mic", name: "Microphone", channels: 0),
        ]
        let rows = AudioOutputList.rows(devices, currentUID: "speakers")
        #expect(rows.map(\.name) == ["AirPods", "MacBook Pro Speakers"])
        #expect(rows.map(\.id) == ["pods", "speakers"])
    }

    @Test("The current UID marks exactly one row, an unknown one marks none")
    func currentRow() {
        let devices = [device("a"), device("b"), device("c")]
        #expect(AudioOutputList.rows(devices, currentUID: "b").map(\.isCurrent) == [false, true, false])
        #expect(AudioOutputList.rows(devices, currentUID: "zzz").allSatisfy { !$0.isCurrent })
        #expect(AudioOutputList.rows(devices, currentUID: nil).allSatisfy { !$0.isCurrent })
    }

    @Test("Rows sort by name in the Finder's order and never move the current one to the top")
    func ordering() {
        let devices = [device("1", name: "zeta"), device("2", name: "Alpha"), device("3", name: "beta")]
        #expect(AudioOutputList.rows(devices, currentUID: "1").map(\.name) == ["Alpha", "beta", "zeta"])
        #expect(AudioOutputList.rows(devices, currentUID: "2").map(\.name) == ["Alpha", "beta", "zeta"])
        let numbered = [device("1", name: "Output 10"), device("2", name: "Output 2")]
        #expect(AudioOutputList.rows(numbered, currentUID: nil).map(\.name) == ["Output 2", "Output 10"])
    }

    @Test("Two devices with the same name sort by UID")
    func tieBreak() {
        let devices = [device("uid-b", name: "Same"), device("uid-a", name: "Same")]
        #expect(AudioOutputList.rows(devices, currentUID: nil).map(\.id) == ["uid-a", "uid-b"])
    }

    @Test("A long name is cut to the maximum length")
    func longName() {
        let name = String(repeating: "x", count: 120)
        let rows = AudioOutputList.rows([device("a", name: name)], currentUID: nil)
        #expect(rows.first?.name.count == AudioOutputList.maximumNameLength)
        #expect(AudioOutputList.maximumNameLength == 80)
    }

    @Test("The symbol follows the transport")
    func symbols() {
        #expect(AudioOutputList.symbol(for: .builtIn) == "laptopcomputer")
        #expect(AudioOutputList.symbol(for: .bluetooth) == "headphones")
        #expect(AudioOutputList.symbol(for: .hdmi) == "display")
        #expect(AudioOutputList.symbol(for: .displayPort) == "display")
        #expect(AudioOutputList.symbol(for: .airPlay) == "airplayaudio")
        #expect(AudioOutputList.symbol(for: .usb) == "hifispeaker.fill")
        #expect(AudioOutputList.symbol(for: .other) == "speaker.wave.2")
        let rows = AudioOutputList.rows([device("a", transport: .hdmi)], currentUID: nil)
        #expect(rows.first?.symbol == "display")
    }

    @Test("The picker is offered from two rows on")
    func offersPicker() {
        let none: [AudioOutputRow] = []
        let one = AudioOutputList.rows([device("a")], currentUID: "a")
        let two = AudioOutputList.rows([device("a"), device("b")], currentUID: "a")
        #expect(!AudioOutputList.offersPicker(none))
        #expect(!AudioOutputList.offersPicker(one))
        #expect(AudioOutputList.offersPicker(two))
    }
}

@Suite("AudioOutputSwitch")
struct AudioOutputSwitchTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("The switch is pending until the default equals the target or three seconds pass")
    func states() {
        let output = AudioOutputSwitch(targetUID: "B", startedAt: start)
        #expect(output.state(currentUID: "A", now: start.addingTimeInterval(1)) == .pending)
        #expect(output.state(currentUID: "B", now: start.addingTimeInterval(1)) == .done)
        #expect(output.state(currentUID: nil, now: start.addingTimeInterval(1)) == .pending)
    }

    @Test("The timeout acts exactly at its edge")
    func timeoutEdge() {
        let output = AudioOutputSwitch(targetUID: "B", startedAt: start)
        #expect(output.state(currentUID: "A", now: start.addingTimeInterval(2.999)) == .pending)
        #expect(output.state(currentUID: "A", now: start.addingTimeInterval(3)) == .gaveUp)
        #expect(AudioOutputList.switchTimeout == 3)
    }

    @Test("A target reached late is still done")
    func lateDone() {
        let output = AudioOutputSwitch(targetUID: "B", startedAt: start)
        #expect(output.state(currentUID: "B", now: start.addingTimeInterval(5)) == .done)
    }
}
