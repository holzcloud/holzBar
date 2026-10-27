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
        #expect(WidgetKind(rawValue: "script") == .script)
        #expect(WidgetKind(rawValue: "chart") == nil)
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
        // The twelve formats of the sources, and the three widths that belong to the script kind
        // alone (D-23).
        #expect(Set(WidgetSource.allCases.flatMap(\.presets)).count == 12)
        #expect(WidgetKind.scriptPresets == [.narrowText, .mediumText, .wideText])
        #expect(WidgetPreset.allCases.count == 15)
        let sourcePresets = Set(WidgetSource.allCases.flatMap(\.presets))
        #expect(sourcePresets.isDisjoint(with: WidgetKind.scriptPresets))
        #expect(sourcePresets.union(WidgetKind.scriptPresets).count == WidgetPreset.allCases.count)
        #expect(WidgetKind.defaultScriptPreset == .mediumText)
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
                "buttonShowsSymbol", "buttonTitle", "id", "kind", "mediaOnlyWhenActive", "preset", "showsSeconds",
                "showsSymbol", "source", "timerMinutes", "uses24HourClock",
            ]
        )
        let labels = Mirror(reflecting: button).children.compactMap(\.label)
        #expect(labels.allSatisfy { !$0.lowercased().contains("shortcut") })
    }

    @Test("A thirteenth widget is dropped (D-05)")
    func capIsTwelve() throws {
        #expect(WidgetDefinition.maximumCount == 12)
        let thirteen = (0..<13).map { _ in element() }
        let list = WidgetList.decode(try data(thirteen), now: now)
        #expect(list.count == 12)
        #expect(list.map(\.id.uuidString) == thirteen.prefix(12).compactMap { $0["id"] as? String })
    }

    @Test("An element of an unknown kind or source is skipped and the rest is kept")
    func lossyDecoding() throws {
        let first = element()
        let third = element(source: "cpu")
        let json = try data([
            first,
            element(kind: "chart"),
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

    @Test("A button shows its symbol when it asks for it or has no title (D-20)")
    func buttonShowsSymbolOnly() {
        var button = WidgetDefinition.button(title: "Go")
        #expect(button.showsButtonSymbolOnly)
        button.buttonShowsSymbol = false
        #expect(!button.showsButtonSymbolOnly)
        button.buttonTitle = ""
        #expect(button.showsButtonSymbolOnly)
        let text = WidgetDefinition.text(source: .cpu, uses24HourClock: false, now: now)
        #expect(!text.showsButtonSymbolOnly)
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

    @Test("A normalised list holds at most the cap of validated widgets without unknown fields (D-25, T-12-04)")
    func normalisation() throws {
        let elements = (0...WidgetDefinition.maximumCount).map { index in
            element(source: "cpu", ["refreshSeconds": 0, "extra": "x\(index)"])
        }
        let normalized = try #require(WidgetList.normalized(try data(elements), now: now))
        let objects = try #require(try JSONSerialization.jsonObject(with: normalized) as? [[String: Any]])
        #expect(objects.count == WidgetDefinition.maximumCount)
        #expect(objects.allSatisfy { $0["extra"] == nil })
        #expect(objects.allSatisfy { ($0["refreshSeconds"] as? Int) == 2 })
        #expect(WidgetList.normalized(normalized, now: now) == normalized)
    }

    // MARK: Script widgets (D-12, D-23, D-25)

    @Test("A list written by stage 1 decodes unchanged (D-23)")
    func stageOneListDecodesUnchanged() throws {
        let clock = element(source: "dateTime", ["preset": "weekdayAndTime", "showsSymbol": false, "uses24HourClock": true])
        let cpu = element(source: "cpu", ["preset": "percent", "refreshSeconds": 10])
        let button = element(kind: "button", ["buttonTitle": "Focus", "buttonShowsSymbol": false])
        let list = WidgetList.decode(try data([clock, cpu, button]), now: now)
        #expect(list.map(\.kind) == [.text, .text, .button])
        #expect(list.map(\.preset) == [.weekdayAndTime, .percent, .time])
        #expect(list[1].refreshSeconds == 10)
        #expect(list[2].buttonTitle == "Focus")
        #expect(!list[2].buttonShowsSymbol)
    }

    @Test("A script definition round-trips and its JSON holds no script name (D-25)")
    func scriptRoundTripWithoutName() throws {
        var script = WidgetDefinition.script()
        script.preset = .wideText
        script.showsSymbol = true
        let clock = text(.dateTime)
        let encoded = try #require(WidgetList.encoded([clock, script]))
        let decoded = WidgetList.decode(encoded, now: now)
        #expect(decoded == [clock, script])
        #expect(WidgetList.encoded(decoded) == encoded)
        let objects = try #require(try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        let keys = try #require(objects.last).keys.sorted()
        #expect(keys.allSatisfy { !$0.lowercased().contains("script") })
        #expect(
            keys == [
                "buttonShowsSymbol", "buttonTitle", "id", "kind", "mediaOnlyWhenActive", "preset", "showsSeconds",
                "showsSymbol", "source", "timerMinutes", "uses24HourClock",
            ]
        )
        #expect(objects.last?["kind"] as? String == "script")
        #expect(objects.last?["preset"] as? String == "wideText")
        let labels = Mirror(reflecting: script).children.compactMap(\.label)
        #expect(labels.allSatisfy { !$0.lowercased().contains("script") })
    }

    @Test("A new script widget is medium wide with no symbol and is valid without anything else")
    func newScriptWidget() {
        let script = WidgetDefinition.script()
        #expect(script.kind == .script)
        #expect(script.preset == .mediumText)
        #expect(!script.showsSymbol)
        #expect(script.symbolName == "terminal")
        #expect(WidgetDefinition.scriptSymbolName == "terminal")
        #expect(script.validated(now: now) == script)
        #expect(script.autosaveName == "holzBar.Widget.\(script.id.uuidString)")
        #expect(WidgetDefinition.script().id != script.id)
    }

    @Test("A script widget keeps a width and its symbol; a width of another kind is not kept (D-12)")
    func scriptPresetValidation() {
        for width in WidgetKind.scriptPresets {
            var script = WidgetDefinition.script()
            script.preset = width
            script.showsSymbol = true
            let valid = script.validated(now: now)
            #expect(valid?.preset == width)
            #expect(valid?.showsSymbol == true)
        }
        var foreign = WidgetDefinition.script()
        foreign.preset = .gigabytesFree
        #expect(foreign.validated(now: now)?.preset == .mediumText)
        // A text widget or a button with a script width goes back to its own default.
        #expect(text(.cpu, preset: .wideText).validated(now: now)?.preset == .percent)
        #expect(text(.dateTime, preset: .narrowText).validated(now: now)?.preset == .time)
        var button = WidgetDefinition.button(title: "Go")
        button.preset = .wideText
        #expect(button.validated(now: now)?.preset == WidgetSource.dateTime.defaultPreset)
    }

    @Test("A script widget has no source-specific option (D-23)")
    func scriptKeepsNoSourceOption() {
        let script = WidgetDefinition(
            id: UUID(),
            kind: .script,
            source: .countdown,
            preset: .wideText,
            showsSeconds: true,
            refreshSeconds: 3,
            countdownTarget: now.addingTimeInterval(60),
            buttonTitle: "Leftover"
        )
        let valid = script.validated(now: now)
        #expect(valid?.source == .dateTime)
        #expect(valid?.showsSeconds == false)
        #expect(valid?.refreshSeconds == nil)
        #expect(valid?.countdownTarget == nil)
        #expect(valid?.buttonTitle == "")
        #expect(valid?.preset == .wideText)
    }

    @Test("A script widget reads on events only, never on a timer (D-14, D-23)")
    func scriptCadenceIsEventOnly() {
        #expect(WidgetCadence(definition: WidgetDefinition.script()) == .eventOnly)
        var wide = WidgetDefinition.script()
        wide.preset = .wideText
        #expect(WidgetCadence(definition: wide) == .eventOnly)
        #expect(WidgetRefreshPolicy.nextFire(for: .eventOnly, date: now, calendar: Calendar(identifier: .gregorian), isLowPowerMode: false) == nil)
    }

    @Test("Scripts count towards the cap of widgets (D-05)")
    func scriptsCountTowardsTheCap() throws {
        let scripts = (0...WidgetDefinition.maximumCount).map { _ in element(kind: "script", ["preset": "narrowText"]) }
        let list = WidgetList.decode(try data(scripts), now: now)
        #expect(list.count == WidgetDefinition.maximumCount)
        #expect(list.allSatisfy { $0.kind == .script && $0.preset == .narrowText })
    }

    @Test("Each kind has its symbol in lists and pictures")
    func symbolNames() {
        #expect(text(.battery).symbolName == "battery.75percent")
        #expect(WidgetDefinition.button(title: "Go").symbolName == WidgetDefinition.buttonSymbolName)
        #expect(WidgetDefinition.script().symbolName == WidgetDefinition.scriptSymbolName)
    }

    // MARK: Built-in items (Phase 79)

    @Test("A built-in item keeps its item and the one option that item has")
    func builtInKeepsItsOption() throws {
        var timer = WidgetDefinition.builtIn(.timer)
        timer.timerMinutes = 500
        timer.mediaOnlyWhenActive = true
        timer.launcherBundleID = "com.apple.Music"
        let validTimer = try #require(timer.validated(now: now))
        #expect(validTimer.builtIn == .timer)
        #expect(validTimer.timerMinutes == 60)
        #expect(!validTimer.mediaOnlyWhenActive)
        #expect(validTimer.launcherBundleID == nil)

        var media = WidgetDefinition.builtIn(.media)
        media.mediaOnlyWhenActive = true
        media.timerMinutes = 25
        let validMedia = try #require(media.validated(now: now))
        #expect(validMedia.mediaOnlyWhenActive)
        #expect(validMedia.timerMinutes == ItemTimer.defaultMinutes)

        let launcher = WidgetDefinition.builtIn(.launcher, launcherBundleID: "com.apple.Music")
        #expect(launcher.validated(now: now)?.launcherBundleID == "com.apple.Music")
    }

    @Test("A launcher keeps only a bundle identifier; any other text is dropped")
    func launcherNeedsABundleIdentifier() throws {
        for text in ["", "Music", "../../etc/passwd", "com.apple.Music\n", "https://example.com"] {
            let launcher = WidgetDefinition.builtIn(.launcher, launcherBundleID: text)
            let valid = try #require(launcher.validated(now: now))
            #expect(valid.launcherBundleID == nil, "\(text)")
        }
    }

    @Test("A built-in widget without an item is not a widget; other kinds forget the item")
    func builtInNeedsAnItem() throws {
        var none = WidgetDefinition.builtIn(.focus)
        none.builtIn = nil
        #expect(none.validated(now: now) == nil)

        var other = text(.battery)
        other.builtIn = .timer
        other.timerMinutes = 30
        other.launcherBundleID = "com.apple.Music"
        let valid = try #require(other.validated(now: now))
        #expect(valid.builtIn == nil)
        #expect(valid.timerMinutes == ItemTimer.defaultMinutes)
        #expect(valid.launcherBundleID == nil)
    }

    @Test("Built-in items round-trip through the stored list and share the cap")
    func builtInRoundTrip() throws {
        let items = BuiltInItem.allCases.map { WidgetDefinition.builtIn($0, launcherBundleID: "com.apple.Music") }
        let encoded = try #require(WidgetList.encoded(items))
        let decoded = WidgetList.decode(encoded, now: now)
        #expect(decoded == items.compactMap { $0.validated(now: now) })
        #expect(decoded.map(\.builtIn) == BuiltInItem.allCases)

        let many = (0...WidgetDefinition.maximumCount).map { _ in WidgetDefinition.builtIn(.launcher, launcherBundleID: "com.apple.Music") }
        let capped = WidgetList.decode(try #require(WidgetList.encoded(many)), now: now)
        #expect(capped.count == WidgetDefinition.maximumCount)
    }

    @Test("An item of a kind of this build that has no item field, or an unknown item, is skipped")
    func builtInUnknownItem() throws {
        let missing = element(kind: "builtIn")
        let unknown = element(kind: "builtIn", ["builtIn": "teleport"])
        let good = element(kind: "builtIn", ["builtIn": "focus"])
        let list = WidgetList.decode(try data([missing, unknown, good]), now: now)
        #expect(list.map(\.builtIn) == [.focus])
    }

    @Test("A built-in item reads on events only; its symbol is its item's")
    func builtInCadenceAndSymbol() {
        for item in BuiltInItem.allCases {
            let widget = WidgetDefinition.builtIn(item)
            #expect(WidgetCadence(definition: widget) == .eventOnly)
            #expect(widget.symbolName == item.symbolName)
        }
    }
}
