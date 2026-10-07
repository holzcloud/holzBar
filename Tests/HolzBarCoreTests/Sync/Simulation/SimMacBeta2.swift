import Foundation

/// The 0.0.7-beta2 peer. It never reads or writes the folder, but its users still edit settings and its
/// load-time writers run at every launch (analysis Appendix A items 1 to 4):
///
/// - the hotkey loader drops duplicate combinations and writes the dictionary back;
/// - `ItemSpacingOffset` and `RehideInterval` are clamped to their ranges and written back;
/// - the appearance, groups and icon values are decoded and re-encoded (missing fields filled with defaults,
///   unknown fields dropped, key order changed).
///
/// Every such write is recorded as an automatic write in the trace. They are exactly what a redesigned
/// peer must not mistake for a user change (INV-A5).
struct SimMacBeta2: SimSyncBrain {
    var kind: SimMacVersion { .beta2 }

    /// The JSON-shaped keys the app re-encodes on load.
    static let reencodedKeys = ["IceIcon", "ItemGroups", "MenuBarAppearanceConfigurationV2"]

    /// The fields the app knows for a key and the defaults it fills in for missing ones.
    private static func rule(for key: String) -> (known: Set<String>, defaults: [String: Any])? {
        switch key {
        case "MenuBarAppearanceConfigurationV2":
            (["token", "tint", "shape", "borderWidth", "shadow"],
             ["tint": "none", "shape": "rounded", "borderWidth": 0, "shadow": false])
        case "ItemGroups":
            (["token", "groups"], ["groups": [Any]()])
        case "IceIcon":
            (["token", "image", "isTemplate", "pad"], ["image": "default", "isTemplate": true])
        default:
            nil
        }
    }

    mutating func launch(_ context: inout SimMacContext) {
        Self.hotkeyWriteBack(&context)
        Self.clamp("ItemSpacingOffset", SimKeys.itemSpacingRange, &context)
        Self.clamp("RehideInterval", SimKeys.rehideIntervalRange, &context)
        for key in Self.reencodedKeys { Self.reencode(key, &context) }
    }

    mutating func quit(_ context: inout SimMacContext) {}
    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {}
    mutating func folderSignal(_ context: inout SimMacContext) {}
    mutating func timerFired(tag: String, _ context: inout SimMacContext) {}
    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {}
    func heldTokens(inFile path: String, data: Data) -> Set<String> { [] }

    // MARK: Load-time writers

    /// `HotkeysSettings.loadInitialState`: a hotkey whose combination an earlier one uses is dropped, and the
    /// dictionary is written back with `Defaults.set` either way.
    private static func hotkeyWriteBack(_ context: inout SimMacContext) {
        guard case .dictionary(let hotkeys)? = context.defaults["Hotkeys"] else { return }
        var kept: [String: SimValue] = [:]
        var used = Set<Int>()
        for action in hotkeys.keys.sorted() {
            guard let value = hotkeys[action] else { continue }
            if case .dictionary(let fields) = value, case .int(let combo)? = fields["combo"] {
                guard used.insert(combo).inserted else { continue }
            }
            kept[action] = value
        }
        context.defaults["Hotkeys"] = .dictionary(kept)
        context.reportAutomaticWrite(unit: "Hotkeys")
    }

    /// `GeneralSettings.loadInitialState`: numeric settings are clamped and assigned, which saves them again.
    private static func clamp(_ key: String, _ range: ClosedRange<Int>, _ context: inout SimMacContext) {
        guard let value = context.defaults[key] else { return }
        if case .int(let number) = value {
            context.defaults[key] = .int(min(max(number, range.lowerBound), range.upperBound))
        }
        context.reportAutomaticWrite(unit: key)
    }

    /// Decode and re-encode: fill missing fields, drop unknown fields, write the keys in sorted order.
    private static func reencode(_ key: String, _ context: inout SimMacContext) {
        guard case .data(let bytes)? = context.defaults[key], let rule = rule(for: key),
              var object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        else { return }
        for field in object.keys where !rule.known.contains(field) { object[field] = nil }
        for (field, value) in rule.defaults where object[field] == nil { object[field] = value }
        guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        context.defaults[key] = .data(encoded)
        context.reportAutomaticWrite(unit: key)
    }

    // MARK: Fixtures for the values these writers touch

    /// The way the app that wrote the value ordered and shaped it: keys in reverse order, an unknown field
    /// from a newer build, and some fields missing. The load-time re-encode changes all three.
    static func userEncodedJSON(token: String, extra: [String: String] = ["futureField": "x"]) -> Data {
        var parts = ["\"token\":\"\(token)\""]
        for (field, value) in extra.sorted(by: { $0.key < $1.key }) { parts.append("\"\(field)\":\"\(value)\"") }
        return Data(("{" + parts.reversed().joined(separator: ",") + "}").utf8)
    }
}
