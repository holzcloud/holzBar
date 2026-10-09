//
//  SyncUnits.swift
//  holzBar
//

import Foundation

/// The macOS generation a Mac belongs to, as far as sync is concerned.
///
/// The macOS 27 arrangement, the layout profiles and the known applications of macOS 27 are
/// authored and applied only by macOS 27 Macs; every other Mac relays them untouched.
nonisolated enum SyncGeneration: Sendable {
    /// macOS 26 and earlier.
    case g26
    /// macOS 27 and later.
    case g27

    /// The generation of the Mac that runs `backend`.
    init(backend: MenuBarBackendKind) {
        switch backend {
        case .accessibility27:
            self = .g27
        case .windowList, .service26:
            self = .g26
        }
    }
}

/// Why a stored key never syncs.
nonisolated enum SyncLocalReason: Sendable {
    /// The arrangement before macOS 27 (`ItemSections`): each Mac keeps its own.
    case arrangement26
    /// What this Mac learned about its own items.
    case learned
    /// A step this Mac does once.
    case flag
    /// Which profile applies here now.
    case profileContext
    /// Tuning of this Mac.
    case tuning
    /// A setting of this Mac, or of sync itself.
    case localSetting
    /// A key of Ice that only the import of Ice's settings reads.
    case iceEra
}

/// How the unit table treats a stored key.
nonisolated enum SyncKeyClass: Equatable, Sendable {
    /// The key is one unit, named `unit`.
    case whole(unit: String)
    /// The key is one half of the unit `HolzBarIcon` (the image and its template flag).
    case holzBarIconPart
    /// The key is a dictionary or a set whose items are the units of the family.
    case split(family: String)
    /// `MacOS27Layout`: the family `l27`, one unit per application, macOS 27 only.
    case layout27
    /// `LayoutProfiles`: the family `prof`, one unit per profile, macOS 27 only.
    case profiles
    /// `KnownApplications27`: the set `known27`, macOS 27 only.
    case knownApplications27
    /// The key stays on this Mac.
    case local(SyncLocalReason)
}

/// What the table knows about one unit, or one family of units.
nonisolated struct SyncUnitDescriptor: Sendable {
    /// The unit's name, or the family's name.
    let name: String
    /// The stored keys the unit or family is projected from.
    let storedKeys: [Defaults.Key]
    /// The most bytes a value may take (``size(of:)``).
    let cap: Int
    /// The most items a family holds; `nil` for a whole unit.
    let maximumItems: Int?
    /// The generation that authors and applies the unit; `nil` means every generation.
    let scope: SyncGeneration?
    /// Whether this is a set of strings that joins by union, not a unit.
    let isSet: Bool
    /// Whether this is a family of units.
    let isFamily: Bool
    /// The size of a value against ``cap``.
    let measure: @Sendable (SyncValue) -> Int
    /// Whether `value` can be the value of the unit (the item is `nil` for a whole unit).
    /// A value that fails stays on its Mac and is never written to the defaults.
    let validate: @Sendable (_ item: String?, _ value: SyncValue) -> Bool

    /// The size of `value` against ``cap``.
    func size(of value: SyncValue) -> Int {
        measure(value)
    }

    /// Whether `value` is too large to publish.
    func isOverCap(_ value: SyncValue) -> Bool {
        measure(value) > cap
    }
}

/// The unit table: which stored keys sync, as which units, and with what limits.
///
/// Analysis section 4.2 and decisions D-03 to D-06. A unit key never changes its value
/// format; a changed format, a new field or a widened range gets a new unit and a new
/// ``version``. ``keyClass(_:)`` is one exhaustive `switch`, so a new `Defaults.Key` does not
/// compile until it has a class.
nonisolated struct SyncUnitTable: Sendable {
    /// The table version a device file records (`unitTable`).
    let version: Int

    /// The normalizers that make values of the JSON units comparable.
    let normalizers: SyncNormalizers

    private let wholeDescriptors: [String: SyncUnitDescriptor]
    private let familyDescriptors: [String: SyncUnitDescriptor]
    private let knownItems: [String: Set<String>]
    private let keysByUnit: [String: Defaults.Key]

    // MARK: Names

    /// The unit that holds the holzBar icon and its template flag.
    static let holzBarIconUnit = "HolzBarIcon"

    /// The family of the macOS 27 arrangement, one unit per application (bundle identifier).
    static let layout27Family = "l27"

    /// The family of the layout profiles, one unit per profile (profile ID).
    static let profilesFamily = "prof"

    /// The set of the applications macOS 27 Macs know.
    static let knownApplicationsSet = "known27"

    /// The entries of `RevealRules` this build knows.
    static let revealRuleItems: Set<String> = ["LowBattery", "LowBatteryThreshold", "Offline"]

    /// The prefix of an item hotkey's stored key.
    static let openItemPrefix = HotkeyTarget.itemPrefix

    /// The prefix of a profile hotkey's stored key.
    static let applyProfilePrefix = HotkeyTarget.profilePrefix

    /// The keys that never sync, by prefix: window frames, status item positions, Sparkle
    /// and every key of sync itself. Only holzBar's own keys sync, so these never do.
    static let excludedKeyPrefixes = [
        "NSWindow Frame",
        "NSStatusItem Preferred Position",
        "NSStatusItem Visible",
        "SU",
        "SettingsSync",
    ]

    /// Whether the stored key name is one that never syncs.
    static func isExcluded(storedKey: String) -> Bool {
        excludedKeyPrefixes.contains { storedKey.hasPrefix($0) }
    }

    // MARK: Caps

    /// The most bytes of the holzBar icon unit: the image data.
    static let iconCap = 256 << 10

    /// The most bytes of the appearance and the item groups.
    static let jsonUnitCap = 64 << 10

    /// The most bytes of a layout profile.
    static let profileCap = 64 << 10

    /// The most bytes of an ordinary whole unit.
    static let settingCap = 1 << 10

    /// The most bytes of one item of a small family.
    static let itemCap = 4 << 10

    /// The most UTF-8 bytes of an item key.
    static let maximumItemKeyBytes = 1024

    /// The longest name of a profile, in characters.
    static let maximumProfileNameLength = 200

    // MARK: Classes

    /// The class of every stored key.
    ///
    /// The switch has no `default`, so a key without a class does not compile.
    static func keyClass(_ key: Defaults.Key) -> SyncKeyClass {
        switch key {
        // General.
        case .showHolzBarIcon,
            .useShelf,
            .shelfLocation,
            .shelfDisplays,
            .showsNotchOverflowInShelf,
            .showOnClick,
            .showOnHover,
            .showOnScroll,
            .showOnHoverDelay,
            .autoRehide,
            .rehideStrategy,
            .rehideInterval,
            .tempShowInterval,
            .itemSpacingOffset,
            .holzBarIconShowsCaptureDot,
            // Advanced.
            .enableAlwaysHiddenSection,
            .showAllSectionsOnUserDrag,
            .sectionDividerStyle,
            .hideApplicationMenus,
            .keepsDockIconHidden,
            .enableSecondaryContextMenu,
            .newItemsPlacement,
            .keepLiveActivitiesVisible,
            .autoZenWhileSharingScreen,
            .openHiddenItemsInMenuBar,
            .spacerCount,
            .spacerWidth,
            // The appearance and the groups are whole JSON units.
            .menuBarAppearanceConfigurationV2,
            .itemGroups:
            .whole(unit: key.rawValue)
        case .holzBarIcon, .customHolzBarIconIsTemplate:
            .holzBarIconPart
        case .hotkeys, .itemIcons, .revealRules, .revealOnChangeItems:
            .split(family: key.rawValue)
        case .macOS27Layout:
            .layout27
        case .layoutProfiles:
            .profiles
        case .knownApplications27:
            .knownApplications27
        case .itemSections:
            .local(.arrangement26)
        case .knownItemTags, .titleChangingItemOwners:
            .local(.learned)
        case .macOS27LayoutSeeded,
            .hasMigrated0_8_0,
            .hasMigrated0_10_0,
            .hasMigrated0_10_1,
            .hasMigrated0_11_10,
            .hasMigrated0_11_13,
            .hasMigrated0_11_13_1,
            .hasImportedPreviousSettings:
            .local(.flag)
        case .currentLayoutProfile:
            .local(.profileContext)
        case .macOS27ClickRestoreDelay, .macOS27ShelfWaitsForRefresh:
            .local(.tuning)
        case .syncsSettingsWithICloud, .debugDropsBarrierExitEvent, .debugHangsItemImageCapture:
            .local(.localSetting)
        case .menuBarHasBorder,
            .menuBarBorderColor,
            .menuBarBorderWidth,
            .menuBarHasShadow,
            .menuBarTintKind,
            .menuBarTintColor,
            .menuBarTintGradient,
            .menuBarShapeKind,
            .menuBarFullShapeInfo,
            .menuBarSplitShapeInfo,
            .menuBarAppearanceConfiguration,
            .showSectionDividers,
            .canToggleAlwaysHiddenSection,
            .sections:
            .local(.iceEra)
        }
    }

    /// The stored keys of every synced class, sorted by stored name.
    static var syncedKeys: [Defaults.Key] {
        Defaults.Key.allCases
            .filter { key in
                if case .local = keyClass(key) {
                    return false
                }
                return true
            }
            .sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
    }

    // MARK: Version 1

    /// The unit table of version 1.
    static func version1(normalizers: SyncNormalizers) -> SyncUnitTable {
        var whole: [String: SyncUnitDescriptor] = [:]
        var keysByUnit: [String: Defaults.Key] = [:]
        for key in Defaults.Key.allCases {
            guard case .whole(let unit) = keyClass(key) else {
                continue
            }
            keysByUnit[unit] = key
            switch key {
            case .menuBarAppearanceConfigurationV2:
                whole[unit] = jsonUnit(unit, key: key, validate: normalizers.appearance)
            case .itemGroups:
                whole[unit] = jsonUnit(unit, key: key, validate: normalizers.itemGroups)
            default:
                whole[unit] = settingUnit(unit, key: key)
            }
        }
        whole[holzBarIconUnit] = SyncUnitDescriptor(
            name: holzBarIconUnit,
            storedKeys: [.holzBarIcon, .customHolzBarIconIsTemplate],
            cap: iconCap,
            maximumItems: nil,
            scope: nil,
            isSet: false,
            isFamily: false,
            measure: { value in
                // The cap counts the image, not the envelope around it.
                if case .data(let data)? = value.dictionaryValue?["icon"] {
                    return data.count
                }
                return value.encodedSize
            },
            validate: { _, value in normalizers.holzBarIcon(value) != nil }
        )
        // The set is addressed as a unit name to ask about its scope; it holds no entries.
        whole[knownApplicationsSet] = SyncUnitDescriptor(
            name: knownApplicationsSet,
            storedKeys: [.knownApplications27],
            cap: 0,
            maximumItems: nil,
            scope: .g27,
            isSet: true,
            isFamily: false,
            measure: { $0.encodedSize },
            validate: { _, value in value.arrayValue?.allSatisfy { $0.stringValue != nil } ?? false }
        )
        var families: [String: SyncUnitDescriptor] = [:]
        families[Defaults.Key.hotkeys.rawValue] = family(
            Defaults.Key.hotkeys.rawValue,
            key: .hotkeys,
            cap: 1 << 10,
            scope: nil,
            validate: { item, value in
                guard let item, isItemKey(item), HotkeyTarget(storageKey: item) != nil, case .data(let data) = value else {
                    return false
                }
                // Clearing a hotkey stores JSON `null`.
                return HotkeyStorage.decode(data) != nil || isJSONNull(data)
            }
        )
        families[Defaults.Key.itemIcons.rawValue] = family(
            Defaults.Key.itemIcons.rawValue,
            key: .itemIcons,
            cap: itemCap,
            scope: nil,
            validate: { item, value in
                guard let item, isItemKey(item), let text = value.stringValue else {
                    return false
                }
                return ItemIconChoice.parse(text) != nil
            }
        )
        families[Defaults.Key.revealRules.rawValue] = family(
            Defaults.Key.revealRules.rawValue,
            key: .revealRules,
            cap: 64,
            scope: nil,
            validate: { item, value in
                switch item {
                case "LowBattery", "Offline":
                    value.boolValue != nil
                case "LowBatteryThreshold":
                    value.integerValue.map { (1...100).contains($0) } ?? false
                default:
                    false
                }
            }
        )
        families[Defaults.Key.revealOnChangeItems.rawValue] = family(
            Defaults.Key.revealOnChangeItems.rawValue,
            key: .revealOnChangeItems,
            cap: 64,
            scope: nil,
            validate: { item, value in
                guard let item, isItemKey(item) else {
                    return false
                }
                return value.boolValue != nil
            }
        )
        families[layout27Family] = family(
            layout27Family,
            key: .macOS27Layout,
            cap: 64,
            scope: .g27,
            validate: { item, value in
                guard let item, isItemKey(item), let section = value.integerValue else {
                    return false
                }
                return (0...2).contains(section)
            }
        )
        families[profilesFamily] = family(
            profilesFamily,
            key: .layoutProfiles,
            cap: profileCap,
            scope: .g27,
            validate: { item, value in
                guard let item, isItemKey(item) else {
                    return false
                }
                return isValidProfile(value)
            }
        )
        return SyncUnitTable(
            version: 1,
            normalizers: normalizers,
            wholeDescriptors: whole,
            familyDescriptors: families,
            knownItems: [Defaults.Key.revealRules.rawValue: revealRuleItems],
            keysByUnit: keysByUnit
        )
    }

    // MARK: Descriptors

    private static func settingUnit(_ unit: String, key: Defaults.Key) -> SyncUnitDescriptor {
        let kind = key.settingsKind
        let rule = key.numberRule
        return SyncUnitDescriptor(
            name: unit,
            storedKeys: [key],
            cap: settingCap,
            maximumItems: nil,
            scope: nil,
            isSet: false,
            isFamily: false,
            measure: { $0.encodedSize },
            validate: { _, value in isValid(value, kind: kind, rule: rule) }
        )
    }

    private static func jsonUnit(
        _ unit: String,
        key: Defaults.Key,
        validate normalize: @escaping @Sendable (SyncValue) -> SyncValue?
    ) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: unit,
            storedKeys: [key],
            cap: jsonUnitCap,
            maximumItems: nil,
            scope: nil,
            isSet: false,
            isFamily: false,
            measure: { value in
                if case .data(let data) = value {
                    return data.count
                }
                return value.encodedSize
            },
            validate: { _, value in normalize(value) != nil }
        )
    }

    private static func family(
        _ name: String,
        key: Defaults.Key,
        cap: Int,
        scope: SyncGeneration?,
        validate: @escaping @Sendable (String?, SyncValue) -> Bool
    ) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: name,
            storedKeys: [key],
            cap: cap,
            maximumItems: SyncDeviceFile.maximumEntriesPerFamily,
            scope: scope,
            isSet: false,
            isFamily: true,
            measure: { $0.encodedSize },
            validate: validate
        )
    }

    /// The descriptor of a unit, or `nil` for a unit this build does not know. Such units are
    /// relayed to the other Macs and never applied.
    func descriptor(for key: SyncUnitKey) -> SyncUnitDescriptor? {
        switch key {
        case .whole(let name):
            return wholeDescriptors[name]
        case .split(let family, let item):
            guard let descriptor = familyDescriptors[family] else {
                return nil
            }
            if let known = knownItems[family], !known.contains(item) {
                return nil
            }
            // A hotkey this build has no action for is relayed, not applied.
            if family == Defaults.Key.hotkeys.rawValue, HotkeyTarget(storageKey: item) == nil {
                return nil
            }
            return descriptor
        }
    }

    /// `value` as this build's normalizer writes it, which is how the local value of the unit
    /// compares after the defaults hold it. A unit without a normalizer keeps its value.
    func normalized(_ value: SyncValue, for key: SyncUnitKey) -> SyncValue {
        guard case .whole(let unit) = key else {
            return value
        }
        switch unit {
        case Defaults.Key.menuBarAppearanceConfigurationV2.rawValue:
            return normalizers.appearance(value) ?? value
        case Defaults.Key.itemGroups.rawValue:
            return normalizers.itemGroups(value) ?? value
        case Self.holzBarIconUnit:
            return normalizers.holzBarIcon(value) ?? value
        default:
            return value
        }
    }

    /// Every whole unit of the table, sorted: the units whose absence a join records as the
    /// baseline "unset", so a value the user sets later is captured as a change.
    var wholeUnitKeys: [SyncUnitKey] {
        wholeDescriptors.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .filter { wholeDescriptors[$0]?.isSet == false }
            .map { SyncUnitKey.whole($0) }
    }

    /// The stored key of a whole unit, if the unit is a single stored key.
    func storedKey(forUnit unit: String) -> Defaults.Key? {
        keysByUnit[unit]
    }

    /// Whether this Mac creates entries for the unit.
    func isAuthoredHere(_ key: SyncUnitKey, generation: SyncGeneration) -> Bool {
        guard let descriptor = descriptor(for: key) else {
            return false
        }
        return descriptor.scope.map { $0 == generation } ?? true
    }

    /// Whether this Mac writes the unit's value to its defaults.
    func isApplicableHere(_ key: SyncUnitKey, generation: SyncGeneration) -> Bool {
        isAuthoredHere(key, generation: generation)
    }

    /// Whether the macOS 27 known applications are this Mac's to merge.
    func isKnownApplicationsApplicable(generation: SyncGeneration) -> Bool {
        isApplicableHere(.whole(Self.knownApplicationsSet), generation: generation)
    }

    // MARK: Validation

    /// Whether `item` can name an item of a family.
    static func isItemKey(_ item: String) -> Bool {
        !item.isEmpty && item.utf8.count <= maximumItemKeyBytes
    }

    private static func isJSONNull(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }

    /// Whether `value` is a value of `kind`, in the range of `rule`; a value out of range is
    /// not valid (a local value is clamped before it gets here).
    static func isValid(_ value: SyncValue, kind: SettingsSchema.Kind, rule: SettingsSchema.NumberRule?) -> Bool {
        switch (kind, value) {
        case (.bool, .bool), (.string, .string), (.data, .data), (.date, .date):
            return true
        case (.number, .integer(let number)):
            return isInRange(Double(number), rule: rule)
        case (.number, .real(let number)):
            return number.isFinite && isInRange(number, rule: rule)
        case (.stringArray, .array(let elements)):
            return elements.allSatisfy { $0.stringValue != nil }
        case (.dictionary, .dictionary):
            return true
        default:
            return false
        }
    }

    private static func isInRange(_ number: Double, rule: SettingsSchema.NumberRule?) -> Bool {
        guard let rule else {
            return true
        }
        guard let sanitized = rule.sanitized(NSNumber(value: number)) else {
            return false
        }
        return sanitized.doubleValue == number
    }

    /// Whether `value` is the unit value of a layout profile: a name, the sections of the
    /// applications and, optionally, the known applications.
    static func isValidProfile(_ value: SyncValue) -> Bool {
        guard let fields = value.dictionaryValue, Set(fields.keys).isSubset(of: ["name", "applicationSections", "knownApplications"]) else {
            return false
        }
        guard let name = fields["name"]?.stringValue, !name.isEmpty, name.count <= maximumProfileNameLength else {
            return false
        }
        guard let sections = fields["applicationSections"]?.dictionaryValue else {
            return false
        }
        // sync-lint: ordered every application has to be valid, so the order cannot change the result
        for (application, section) in sections {
            guard isItemKey(application), let number = section.integerValue, (0...2).contains(number) else {
                return false
            }
        }
        if let known = fields["knownApplications"] {
            guard let elements = known.arrayValue, elements.allSatisfy({ $0.stringValue.map(isItemKey) ?? false }) else {
                return false
            }
        }
        return true
    }
}

nonisolated extension SyncUnitTable {
    /// A table of the given descriptors, with no stored keys behind them: whole units and
    /// families are told apart by ``SyncUnitDescriptor/isFamily``. Only tests use it, to build
    /// the small permissive tables the simulator needs; the app uses ``version1(normalizers:)``.
    init(version: Int, descriptors: [SyncUnitDescriptor], normalizers: SyncNormalizers = .canonical) {
        self.init(
            version: version,
            normalizers: normalizers,
            wholeDescriptors: Dictionary(descriptors.filter { !$0.isFamily }.map { ($0.name, $0) }) { first, _ in first },
            familyDescriptors: Dictionary(descriptors.filter(\.isFamily).map { ($0.name, $0) }) { first, _ in first },
            knownItems: [:],
            keysByUnit: [:]
        )
    }
}
