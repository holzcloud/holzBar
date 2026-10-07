import Foundation

// Control engines: deliberately wrong redesigned-style engines the oracles must catch (analysis section 5.6,
// D-11). If one survives, the generator or the oracles are too weak and the gate fails. All of them run in a
// redesigned slot (`kind == .redesign`), so the oracles charge their violations.

/// Writes one shared file stamped with the Mac's own wall-clock date and applies any file with a newer date over
/// its settings. Different clock offsets make it silently overwrite a live user change (INV-S1) and make its
/// decisions depend on the clock (INV-F9).
struct LastWriterWinsByClock: SimSyncBrain {
    static let path = "holzBar/LastWriter.plist"
    static let maximumFileSize = 1 << 20

    var kind: SimMacVersion { .redesign }

    /// The newest file date this Mac has written or applied (volatile).
    private var newest: Date?
    private var lastWritten: String?

    mutating func launch(_ context: inout SimMacContext) {
        newest = nil
        lastWritten = nil
        guard context.enabled, context.folderID != nil else { return }
        applyNewerFile(&context)
        push(&context)
    }

    mutating func quit(_ context: inout SimMacContext) {}

    mutating func processDied() {
        newest = nil
        lastWritten = nil
    }

    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        push(&context)
    }

    mutating func folderSignal(_ context: inout SimMacContext) {
        guard context.enabled else { return }
        applyNewerFile(&context)
    }

    mutating func timerFired(tag: String, _ context: inout SimMacContext) {}

    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        switch command {
        case .turnOn(let folder), .changeFolder(let folder):
            context.enabled = true
            context.folderID = folder
            lastWritten = nil
            applyNewerFile(&context)
            push(&context)
        case .turnOff:
            context.enabled = false
        case .restart:
            context.requestRelaunch()
        case .importFile:
            push(&context)
        case .answer:
            break
        }
    }

    func heldTokens(inFile path: String, data: Data) -> Set<String> {
        guard path == Self.path, let file = Self.parse(data) else { return [] }
        var tokens = Set<String>()
        for value in file.settings.values { tokens.formUnion(value.tokens) }
        return tokens
    }

    // MARK: Format

    static func parse(_ data: Data) -> (modified: Date, writer: String, settings: [String: SimValue])? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let file = object as? [String: Any],
              let modified = file["modified"] as? Date,
              let raw = file["settings"] as? [String: Any]
        else { return nil }
        var settings: [String: SimValue] = [:]
        for (key, element) in raw {
            if let value = SimValue(propertyList: element) { settings[key] = value }
        }
        return (modified, file["writer"] as? String ?? "", settings)
    }

    // MARK: Behaviour

    private func syncedUnits(_ defaults: [String: SimValue], generation: Int) -> [String: SimValue] {
        var result: [String: SimValue] = [:]
        for (unit, value) in SimUnits.units(of: defaults) where SimLocalKeys.isSyncedUnit(unit, generation: generation) {
            result[unit] = value
        }
        return result
    }

    private mutating func applyNewerFile(_ context: inout SimMacContext) {
        let result = context.read(Self.path, maximumBytes: Self.maximumFileSize)
        if result == .notLocal { context.requestDownload(Self.path) }
        guard case .data(let data, let version) = result, let file = Self.parse(data) else { return }
        guard file.writer != context.mac.name else { return }
        if let newest, file.modified <= newest { return }
        for unit in file.settings.keys.sorted() where SimLocalKeys.isSyncedUnit(unit, generation: context.environment.generation) {
            SimUnits.set(unit, to: file.settings[unit], in: &context.defaults)
        }
        newest = file.modified
        context.reportIngest(version: version)
    }

    private mutating func push(_ context: inout SimMacContext) {
        guard context.enabled, context.folderID != nil else { return }
        let settings = syncedUnits(context.defaults, generation: context.environment.generation)
        let rendering = SimValue.dictionary(settings).canonical
        guard rendering != lastWritten else { return }
        let file: [String: Any] = [
            "modified": context.wallClock,
            "writer": context.mac.name,
            "settings": settings.mapValues(\.propertyList),
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0) else { return }
        if context.write(Self.path, data) == .written {
            lastWritten = rendering
            newest = context.wallClock
        }
    }
}

/// Several redesigned-style Macs that write one shared file the way 0.0.7-beta1 does: push five seconds after any
/// change without reading first, apply a newer file silently with remove-missing at launch. It writes the file
/// older peers read (INV-S6, INV-B1) and loses concurrent edits (INV-S1).
struct SharedFileBeta1StyleEngine: SimSyncBrain {
    private var inner = SimMacBeta1()

    var kind: SimMacVersion { .redesign }

    mutating func launch(_ context: inout SimMacContext) { inner.launch(&context) }
    mutating func quit(_ context: inout SimMacContext) { inner.quit(&context) }
    mutating func processDied() { inner.processDied() }
    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        inner.defaultsChanged(origin: origin, units: units, &context)
    }
    mutating func folderSignal(_ context: inout SimMacContext) { inner.folderSignal(&context) }
    mutating func timerFired(tag: String, _ context: inout SimMacContext) { inner.timerFired(tag: tag, &context) }
    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        inner.userCommand(command, &context)
    }

    var hint: String? { inner.hint }
    var openPrompt: SimPrompt? { inner.openPrompt }
    func heldTokens(inFile path: String, data: Data) -> Set<String> { inner.heldTokens(inFile: path, data: data) }
}
