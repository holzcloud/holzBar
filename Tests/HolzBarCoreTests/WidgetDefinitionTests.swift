import Foundation
import Testing
@testable import HolzBarCore

@Suite("WidgetDefinition")
struct WidgetDefinitionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// The JSON of a list of widgets, as a settings file could hold it.
    private func data(_ elements: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: elements)
    }

    private func element(
        _ id: UUID = UUID(),
        kind: String = "text",
        source: String = "dateTime",
        _ extra: [String: Any] = [:]
    ) -> [String: Any] {
        var result: [String: Any] = ["id": id.uuidString, "kind": kind, "source": source]
        result.merge(extra) { _, new in new }
        return result
    }

    private func text(
        _ source: WidgetSource,
        preset: WidgetPreset? = nil,
        showsSeconds: Bool = false,
        refreshSeconds: Int? = nil,
        countdownTarget: Date? = nil
    ) -> WidgetDefinition {
        WidgetDefinition(
            id: UUID(),
            kind: .text,
            source: source,
            preset: preset ?? source.defaultPreset,
            showsSeconds: showsSeconds,
            refreshSeconds: refreshSeconds,
            countdownTarget: countdownTarget
        )
    }

    @Test("Exactly the seven permission-free sources (D-01, D-04)")
    func sources() {
        #expect(
            WidgetSource.allCases.map(\.rawValue)
                == ["dateTime", "battery", "cpu", "memory", "uptime", "freeDisk", "countdown"]
        )
        #expect(WidgetKind(rawValue: "text") == .text)
        #expect(WidgetKind(rawValue: "button") == .button)
        #expect(WidgetKind(rawValue: "script") == nil)
        #expect(WidgetSource(rawValue: "network") == nil)
        #expect(WidgetSource(rawValue: "wifi") == nil)
        #expect(
            WidgetSource.allCases.map(\.symbolName)
                == ["clock", "battery.75percent", "cpu", "memorychip", "power", "internaldrive", "hourglass"]
        )
    }

    @Test("Each source offers a fixed set of presets (D-09)")
    func presets() {
        #expect(WidgetSource.dateTime.presets == [.time, .weekdayAndTime, .dateAndTime, .weekdayDateAndTime])
        #expect(WidgetSource.battery.presets == [.percent, .percentAndState])
        #expect(WidgetSource.cpu.presets == [.percent])
        #expect(WidgetSource.memory.presets == [.percentUsed, .gigabytesUsed])
        #expect(WidgetSource.uptime.presets == [.duration, .compactDuration])
        #expect(WidgetSource.countdown.presets == [.duration, .compactDuration])
        #expect(WidgetSource.freeDisk.presets == [.gigabytesFree, .percentFree])
        #expect(Set(WidgetSource.allCases.flatMap(\.presets)).count == WidgetPreset.allCases.count)
        #expect(WidgetPreset.allCases.count == 12)
        for source in WidgetSource.allCases {
            #expect(source.presets.contains(source.defaultPreset))
        }
        #expect(WidgetSource.dateTime.defaultPreset == .time)
        #expect(WidgetSource.battery.defaultPreset == .percentAndState)
        #expect(WidgetSource.memory.defaultPreset == .percentUsed)
        #expect(WidgetSource.freeDisk.defaultPreset == .gigabytesFree)
    }

    @Test("A definition round-trips through the list unchanged")
    func roundTrip() throws {
        let clock = WidgetDefinition(
            id: UUID(),
            kind: .text,
            source: .dateTime,
            preset: .weekdayAndTime,
            showsSymbol: false,
            uses24HourClock: true,
            showsSeconds: true
        )
        let cpu = text(.cpu, refreshSeconds: 10)
        let countdown = text(.countdown, preset: .compactDuration, countdownTarget: now.addingTimeInterval(7200))
        let button = WidgetDefinition.button(title: "Focus")
        let list = [clock, cpu, countdown, button]
        let encoded = try #require(WidgetList.encoded(list))
        #expect(WidgetList.decode(encoded, now: now) == list)
        #expect(WidgetList.encoded(WidgetList.decode(encoded, now: now)) == encoded)
    }

    @Test("A definition carries no Shortcut name (D-25)")
    func noShortcutName() throws {
        let button = WidgetDefinition.button(title: "Focus")
        let encoded = try #require(WidgetList.encoded([button]))
        let objects = try #require(try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        let keys = try #require(objects.first).keys.sorted()
        #expect(keys.allSatisfy { !$0.lowercased().contains("shortcut") })
        #expect(
            keys == [
                "buttonShowsSymbol", "buttonTitle", "id", "kind", "preset", "showsSeconds", "showsSymbol",
                "source", "uses24HourClock",
            ]
        )
        let labels = Mirror(reflecting: button).children.compactMap(\.label)
        #expect(labels.allSatisfy { !$0.lowercased().contains("shortcut") })
    }

    @Test("A seventh widget is dropped (D-05)")
    func capIsSix() throws {
        #expect(WidgetDefinition.maximumCount == 6)
        let seven = (0..<7).map { _ in element() }
        let list = WidgetList.decode(try data(seven), now: now)
        #expect(list.count == 6)
        #expect(list.map(\.id.uuidString) == seven.prefix(6).compactMap { $0["id"] as? String })
    }

    @Test("An element of an unknown kind or source is skipped and the rest is kept")
    func lossyDecoding() throws {
        let first = element()
        let third = element(source: "cpu")
        let json = try data([
            first,
            element(kind: "script"),
            third,
            element(source: "weather"),
            ["kind": "text", "source": "cpu"],
        ])
        let list = WidgetList.decode(json, now: now)
        #expect(list.map(\.id.uuidString) == [first["id"], third["id"]].compactMap { $0 as? String })
    }

    @Test("Older and newer files decode: only id, kind and source are required")
    func tolerantDecoding() throws {
        let id = UUID()
        let json = try data([element(id, source: "memory", ["futureField": ["nested": true]])])
        let definition = try #require(WidgetList.decode(json, now: now).first)
        #expect(definition.id == id)
        #expect(definition.source == .memory)
        #expect(definition.preset == .percentUsed)
        #expect(definition.showsSymbol)
        #expect(definition.refreshSeconds == 10)
    }

    @Test("A preset that does not belong to the source becomes its default (D-09)")
    func foreignPreset() {
        let clock = text(.dateTime, preset: .gigabytesFree)
        #expect(clock.validated(now: now)?.preset == .time)
        let disk = text(.freeDisk, preset: .weekdayAndTime)
        #expect(disk.validated(now: now)?.preset == .gigabytesFree)
        let battery = text(.battery, preset: .percent)
        #expect(battery.validated(now: now)?.preset == .percent)
    }

    @Test("Seconds only on the clock (D-10)")
    func secondsOnlyOnTheClock() {
        let clock = text(.dateTime, showsSeconds: true)
        #expect(clock.validated(now: now)?.showsSeconds == true)
        for source in WidgetSource.allCases where source != .dateTime {
            let target = source == .countdown ? now.addingTimeInterval(60) : nil
            let widget = text(source, showsSeconds: true, countdownTarget: target)
            #expect(widget.validated(now: now)?.showsSeconds == false, "\(source)")
        }
        #expect(WidgetDefinition.text(source: .dateTime, uses24HourClock: true, now: now).showsSeconds == false)
    }

    @Test("CPU and memory keep their minimum intervals (D-15)")
    func minimumIntervals() {
        #expect(WidgetSource.cpu.refreshRange == 2...60)
        #expect(WidgetSource.memory.refreshRange == 5...300)
        #expect(WidgetSource.cpu.defaultRefreshSeconds == 5)
        #expect(WidgetSource.memory.defaultRefreshSeconds == 10)
        #expect(WidgetSource.dateTime.refreshRange == nil)
        #expect(WidgetSource.battery.defaultRefreshSeconds == nil)
        #expect(WidgetSource.cpu.refreshChoices == [2, 5, 10, 30])
        #expect(WidgetSource.memory.refreshChoices == [5, 10, 30, 60])
        #expect(WidgetSource.freeDisk.refreshChoices.isEmpty)
        #expect(text(.cpu, refreshSeconds: 0).validated(now: now)?.refreshSeconds == 2)
        #expect(text(.cpu, refreshSeconds: -4).validated(now: now)?.refreshSeconds == 2)
        #expect(text(.cpu, refreshSeconds: 100_000).validated(now: now)?.refreshSeconds == 60)
        #expect(text(.cpu, refreshSeconds: nil).validated(now: now)?.refreshSeconds == 5)
        #expect(text(.memory, refreshSeconds: 1).validated(now: now)?.refreshSeconds == 5)
        #expect(text(.memory, refreshSeconds: 999).validated(now: now)?.refreshSeconds == 300)
        #expect(text(.memory, refreshSeconds: nil).validated(now: now)?.refreshSeconds == 10)
        #expect(text(.battery, refreshSeconds: 3).validated(now: now)?.refreshSeconds == nil)
    }

    @Test("A countdown needs a target within about 126 years")
    func countdownTarget() {
        #expect(text(.countdown, countdownTarget: nil).validated(now: now) == nil)
        let near = text(.countdown, countdownTarget: now.addingTimeInterval(-3600))
        #expect(near.validated(now: now) != nil)
        let far = text(.countdown, countdownTarget: now.addingTimeInterval(127 * 365 * 86400))
        #expect(far.validated(now: now) == nil)
        let past = text(.countdown, countdownTarget: now.addingTimeInterval(-127 * 365 * 86400))
        #expect(past.validated(now: now) == nil)
        let clock = text(.dateTime, countdownTarget: now.addingTimeInterval(127 * 365 * 86400))
        #expect(clock.validated(now: now)?.countdownTarget == nil)
    }

    @Test("A new countdown targets the next hour, rounded down to the minute")
    func newCountdown() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000 + 37)
        let widget = WidgetDefinition.text(source: .countdown, uses24HourClock: false, now: start)
        let target = try #require(widget.countdownTarget)
        let expected = ((start.timeIntervalSinceReferenceDate + 3600) / 60).rounded(.down) * 60
        #expect(target.timeIntervalSinceReferenceDate == expected)
        #expect(target > start)
        #expect(target.timeIntervalSince(start) <= 3600)
        #expect(widget.validated(now: start) != nil)
        // The clock starts without a symbol; every other source starts with one.
        #expect(WidgetDefinition.text(source: .dateTime, uses24HourClock: true, now: start).showsSymbol == false)
        #expect(WidgetDefinition.text(source: .battery, uses24HourClock: true, now: start).showsSymbol)
        #expect(WidgetDefinition.text(source: .cpu, uses24HourClock: true, now: start).refreshSeconds == 5)
    }

    @Test("A button title loses control characters, is trimmed and capped")
    func buttonTitleIsCleaned() {
        #expect(WidgetDefinition.maximumTitleLength == 24)
        #expect(WidgetDefinition.button(title: "  Focus  ").validated(now: now)?.buttonTitle == "Focus")
        #expect(WidgetDefinition.button(title: "A\u{0007}B\u{202E}C\u{E000}D\nE").validated(now: now)?.buttonTitle == "ABCDE")
        let long = String(repeating: "x", count: 60)
        #expect(WidgetDefinition.button(title: long).validated(now: now)?.buttonTitle.count == 24)
        #expect(WidgetDefinition.button(title: "").validated(now: now)?.buttonTitle == "")
        #expect(WidgetDefinition.button(title: "\u{200B}\u{202E}").validated(now: now)?.buttonTitle == "")
        #expect(WidgetDefinition.buttonSymbolName == "play.circle")
        let button = WidgetDefinition.button(title: "Go")
        #expect(button.kind == .button)
        #expect(button.buttonShowsSymbol)
    }

    @Test("Autosave names are holzBar.Widget.<uuid> (D-17)")
    func autosaveNames() throws {
        let id = try #require(UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001"))
        let widget = WidgetDefinition.button(title: "Go")
        #expect(WidgetDefinition.autosaveNamePrefix == "holzBar.Widget.")
        #expect(widget.autosaveName == "holzBar.Widget.\(widget.id.uuidString)")
        let named = WidgetDefinition(id: id, kind: .button, source: .dateTime, preset: .time)
        #expect(named.autosaveName == "holzBar.Widget.0A1B2C3D-0000-4000-8000-000000000001")
        #expect(WidgetDefinition.isAutosaveName(named.autosaveName))
        #expect(WidgetDefinition.id(fromAutosaveName: named.autosaveName) == id)
        #expect(!WidgetDefinition.isAutosaveName("holzBar.Group.\(id.uuidString)"))
        #expect(!WidgetDefinition.isAutosaveName("holzBar.Spacer.\(id.uuidString)"))
        #expect(!WidgetDefinition.isAutosaveName("holzBar.Widget."))
        #expect(!WidgetDefinition.isAutosaveName("holzBar.Widget.not-a-uuid"))
        #expect(!WidgetDefinition.isAutosaveName("holzBar.Widget.\(id.uuidString)x"))
        #expect(!WidgetDefinition.isAutosaveName("holzBar.Widget.\(id.uuidString.lowercased())"))
        #expect(!WidgetDefinition.isAutosaveName("holzbar.widget.\(id.uuidString)"))
        #expect(!WidgetDefinition.isAutosaveName(""))
        #expect(WidgetDefinition.id(fromAutosaveName: "holzBar.Widget.") == nil)
    }

    @Test("The first of two equal identifiers wins")
    func duplicateIdentifiers() throws {
        let id = UUID()
        let json = try data([element(id, source: "cpu"), element(id, source: "memory"), element()])
        let list = WidgetList.decode(json, now: now)
        #expect(list.count == 2)
        #expect(list.first?.source == .cpu)
    }

    @Test("Data over the size limit or not a list is refused (T-12-04)")
    func sizeAndShape() throws {
        #expect(WidgetList.maximumDataSize == 65_536)
        let big = Data(repeating: 0x20, count: WidgetList.maximumDataSize + 1)
        #expect(WidgetList.decode(big, now: now).isEmpty)
        #expect(WidgetList.normalized(big, now: now) == nil)
        let object = Data(#"{"id": "x"}"#.utf8)
        #expect(WidgetList.decode(object, now: now).isEmpty)
        #expect(WidgetList.normalized(object, now: now) == nil)
        #expect(WidgetList.normalized(Data("nonsense".utf8), now: now) == nil)
        #expect(WidgetList.normalized(Data("[]".utf8), now: now) == Data("[]".utf8))
    }

    @Test("A normalised list holds at most six validated widgets without unknown fields (D-25, T-12-04)")
    func normalisation() throws {
        let elements = (0..<7).map { index in
            element(source: "cpu", ["refreshSeconds": 0, "extra": "x\(index)"])
        }
        let normalized = try #require(WidgetList.normalized(try data(elements), now: now))
        let objects = try #require(try JSONSerialization.jsonObject(with: normalized) as? [[String: Any]])
        #expect(objects.count == 6)
        #expect(objects.allSatisfy { $0["extra"] == nil })
        #expect(objects.allSatisfy { ($0["refreshSeconds"] as? Int) == 2 })
        #expect(WidgetList.normalized(normalized, now: now) == normalized)
    }
}
