import Foundation

/// The literal model of the 0.0.6 and 0.0.7-beta1 sync peer (A2 section 2.6, "L1"):
///
/// - one shared file `<folder>/holzBar/Settings.plist` with `modified`, `deviceID` and `settings`;
/// - at launch with sync on it applies an acceptable file silently, with remove-missing, then pushes;
/// - it pushes 5 s after any defaults change (user or automatic) without reading first;
/// - Turn On and Change push without reading;
/// - it ignores files over 1 MiB, from its own device, not newer than its last sync, or more than 1 h ahead;
/// - a folder signal with an acceptable file opens an alert: Restart applies and relaunches, Later records nothing.
struct SimMacBeta1: SimSyncBrain {
    static let filePath = "holzBar/Settings.plist"
    static let maximumFileSize = 1 << 20
    static let allowedClockSkew: TimeInterval = 60 * 60
    static let pushDelayMilliseconds: Int64 = 5_000
    static let pushTimerTag = "push"

    static let deviceIDKey = "SettingsSyncDeviceID"
    static let lastSyncedKey = "SettingsSyncLastSynced"
    static let importedFlagKey = "HasImportedIceSettings"

    var kind: SimMacVersion { .beta1 }

    /// The settings of the last pushed file, canonically rendered (nil after launch, Turn On and Change).
    private var lastPushed: String?
    private var pending: AcceptedFile?
    private var prompt: SimPrompt?
    /// Survives relaunches so that prompt IDs stay unique per Mac.
    private var promptCounter = 0

    /// A file that passed `accept`.
    struct AcceptedFile: Equatable, Sendable {
        var modified: Date
        var settings: [String: SimValue]
        var version: Int
    }

    // MARK: Hooks

    mutating func launch(_ context: inout SimMacContext) {
        lastPushed = nil
        pending = nil
        prompt = nil
        guard context.enabled, context.folderID != nil else { return }
        // 1. In AppDelegate.init, on the main thread: a coordinated read that may block.
        if let file = acceptedFile(&context) {
            apply(file, &context)
        }
        // 2. performSetup: isEnabled false to true pushes.
        push(&context)
    }

    mutating func quit(_ context: inout SimMacContext) {
        pending = nil
        prompt = nil
    }

    mutating func processDied() {
        pending = nil
        prompt = nil
        lastPushed = nil
    }

    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        schedulePush(&context)
    }

    mutating func folderSignal(_ context: inout SimMacContext) {
        guard context.enabled, prompt == nil, let file = acceptedFile(&context) else { return }
        pending = file
        promptCounter += 1
        // The alert names no setting, so nothing is shown that a later answer could supersede.
        let alert = SimPrompt(id: promptCounter, title: "Settings changed on another Mac", shown: [])
        prompt = alert
        context.reportPrompt(alert)
    }

    mutating func timerFired(tag: String, _ context: inout SimMacContext) {
        if tag == Self.pushTimerTag { push(&context) }
    }

    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        switch command {
        case .turnOn(let folder), .changeFolder(let folder):
            context.enabled = true
            context.folderID = folder
            lastPushed = nil
            push(&context)
        case .turnOff:
            context.enabled = false
            context.cancelTimer(tag: Self.pushTimerTag)
            pending = nil
            prompt = nil
        case .restart:
            context.requestRelaunch()
        case .importFile:
            schedulePush(&context)
        case .answer(let answer):
            guard prompt != nil else { return }
            let file = pending
            prompt = nil
            pending = nil
            // "Restart" applies the file as at launch and relaunches; "Later" records nothing.
            if answer == .use, let file {
                apply(file, &context)
                context.requestRelaunch()
            }
        }
    }

    var openPrompt: SimPrompt? { prompt }
    var hint: String? { prompt == nil ? nil : "Settings changed on another Mac" }

    func heldTokens(inFile path: String, data: Data) -> Set<String> {
        guard path == Self.filePath, let parsed = Self.parse(data) else { return [] }
        var tokens = Set<String>()
        for value in parsed.settings.values { tokens.formUnion(value.tokens) }
        return tokens
    }

    // MARK: File format

    /// Decodes the plist. Returns `nil` unless it parses with a date `modified` and a dictionary `settings`.
    static func parse(_ data: Data) -> (modified: Date, deviceID: String?, device: String?, settings: [String: SimValue])? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let file = object as? [String: Any],
              let modified = file["modified"] as? Date,
              let raw = file["settings"] as? [String: Any]
        else { return nil }
        var settings: [String: SimValue] = [:]
        for (key, element) in raw {
            if let value = SimValue(propertyList: element) { settings[key] = value }
        }
        return (modified, file["deviceID"] as? String, file["device"] as? String, settings)
    }

    /// `accept(file)` of A2 section 2.6, over a bounded coordinated read of the file.
    private func acceptedFile(_ context: inout SimMacContext) -> AcceptedFile? {
        let result = context.read(Self.filePath, maximumBytes: Self.maximumFileSize)
        // A coordinated read of a dataless file downloads it; the content is there at the next signal.
        if result == .notLocal { context.requestDownload(Self.filePath) }
        guard case .data(let data, let version) = result, let file = Self.parse(data) else { return nil }
        if let deviceID = file.deviceID {
            guard deviceID != ownDeviceID(context) else { return nil }
        } else if let device = file.device {
            guard device != context.environment.computerName else { return nil }
        }
        guard file.modified > lastSynced(context) else { return nil }
        guard file.modified <= context.wallClock.addingTimeInterval(Self.allowedClockSkew) else { return nil }
        return AcceptedFile(modified: file.modified, settings: file.settings, version: version)
    }

    private func ownDeviceID(_ context: SimMacContext) -> String? {
        if case .string(let id)? = context.defaults[Self.deviceIDKey] { return id }
        return nil
    }

    private func lastSynced(_ context: SimMacContext) -> Date {
        if case .int(let milliseconds)? = context.defaults[Self.lastSyncedKey] {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        return Date(timeIntervalSince1970: 0)
    }

    private static func milliseconds(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: Apply and push

    /// Remove-missing (F-60): every importable key the file lacks is removed. Returns the removed keys.
    @discardableResult
    static func removesMissing(_ settings: [String: SimValue], from defaults: inout [String: SimValue]) -> [String] {
        var removed: [String] = []
        for key in SimKeys.importableKeys where !SimKeys.isLocal(key) && settings[key] == nil {
            if defaults.removeValue(forKey: key) != nil { removed.append(key) }
        }
        return removed
    }

    private func apply(_ file: AcceptedFile, _ context: inout SimMacContext) {
        Self.removesMissing(file.settings, from: &context.defaults)
        for key in file.settings.keys.sorted() {
            // Unknown keys and keys of the wrong type are ignored.
            guard let expected = SimKeys.importable[key], !SimKeys.isLocal(key),
                  let value = file.settings[key], value.kind == expected
            else { continue }
            context.defaults[key] = value
        }
        context.defaults[Self.importedFlagKey] = .bool(true)
        context.defaults[Self.lastSyncedKey] = .int(Self.milliseconds(of: file.modified))
        context.reportIngest(version: file.version)
    }

    private func schedulePush(_ context: inout SimMacContext) {
        guard context.enabled else { return }
        context.cancelTimer(tag: Self.pushTimerTag)
        context.scheduleTimer(afterMilliseconds: Self.pushDelayMilliseconds, tag: Self.pushTimerTag)
    }

    private func currentSettings(_ defaults: [String: SimValue]) -> [String: SimValue] {
        var settings: [String: SimValue] = [:]
        for key in SimKeys.importableKeys where !SimKeys.isLocal(key) {
            if let value = defaults[key] { settings[key] = value }
        }
        return settings
    }

    /// Writes the file without reading it first, when the encoded settings differ from the last push.
    private mutating func push(_ context: inout SimMacContext) {
        guard context.enabled, context.folderID != nil else { return }
        let settings = currentSettings(context.defaults)
        let rendering = SimValue.dictionary(settings).canonical
        guard rendering != lastPushed else { return }
        let deviceID: String
        if let existing = ownDeviceID(context) {
            deviceID = existing
        } else {
            deviceID = "DEV-" + String(context.random.next(), radix: 16)
            context.defaults[Self.deviceIDKey] = .string(deviceID)
        }
        let file: [String: Any] = [
            "modified": context.wallClock,
            "deviceID": deviceID,
            "settings": settings.mapValues(\.propertyList),
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0) else { return }
        if context.write(Self.filePath, data) == .written {
            lastPushed = rendering
            context.defaults[Self.lastSyncedKey] = .int(Self.milliseconds(of: context.wallClock))
        }
    }
}
