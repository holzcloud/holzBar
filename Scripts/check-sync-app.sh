#!/usr/bin/env bash
#
# Runs the app side of the settings sync without Xcode: the normalizers on the main actor, and the
# host (`SettingsSync`) against real files, as one Mac after another.
#
# Settings sync is paused in the shipped build (`SettingsSyncPause`), and the Core package cannot test
# the app's code. This script builds the app module in a temporary copy, where the pause is switched
# off and the state folders are redirected, adds a small program that plays the Macs, and runs it:
#
#   normalizers  Every normalizer of `SyncModelNormalizers` runs once on the main thread (they assume
#                the main actor and trap anywhere else): a stored default is applicable and canonical, a
#                value with an unknown field or no JSON is not.
#   found        A Mac that comes from the pause (sync on, a bookmark, an old sync ID, the bookkeeping
#                keys of 0.0.7-beta1) founds the group in an empty folder at launch, writes only its own
#                device file under holzBar/Macs, rotates its ID once, and leaves every key of the earlier
#                builds where it was.
#   join         A second Mac joins that folder, shows the Restart hint and keeps its value; at its next
#                launch (apply) it has the first Mac's value.
#   conflict     While the first Mac runs, another Mac's file with another value arrives: the folder
#                watcher hears it, the hint asks, the answer Keep writes the Mac's value, the hint goes.
#   edit         A change of a setting is captured after the engine's delay and written to the own file.
#                (The order of the run is found, conflict, edit, join, apply: the joining Mac ends with the
#                edited value.)
#
# It uses a preferences domain of its own (com.holzcloud.holzBar.synccheck, embedded in the program), a
# temporary sync folder and temporary state folders, and removes all of them at the end. It never
# touches holzBar's own preferences or Application Support folder. It needs only the Command Line
# Tools; `SDK=/path/to/MacOSX.sdk` overrides the 26.5 SDK (see typecheck-app.sh).

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

work="$(mktemp -d)"
cleanup() {
    if [ -x "$work/check" ]; then
        "$work/check" reset "$work/folder" "$work/state" > /dev/null 2>&1 || true
    fi
    # What removing the domain leaves behind: its (empty) file.
    rm -f "$HOME/Library/Preferences/com.holzcloud.holzBar.synccheck.plist"
    rm -rf "$work"
}
trap cleanup EXIT

mkdir "$work/src" "$work/folder"
cp -R "$root/holzBar" "$work/src/holzBar"
cp -R "$root/Shared" "$work/src/Shared"
# The entry point of the app; the check has its own.
rm "$work/src/holzBar/Main/HolzBarApp.swift"

# The pause is switched off in the copy only, and the state folders are the check's own.
python3 - "$work/src" <<'PYTHON'
import re
import sys

source = sys.argv[1]

path = source + "/holzBar/Core/SettingsSyncPause.swift"
text = open(path).read()
text, count = re.subn(r"static let isPaused = true", "static let isPaused = false", text)
assert count == 1, "SettingsSyncPause.isPaused not found"
open(path, "w").write(text)

path = source + "/holzBar/Utilities/Sync/SyncFileCoordination.swift"
text = open(path).read()
start = text.index("    static func makeStateStore() -> SyncStateStore {")
end = text.index("    // MARK: Presenters")
text = text[:start] + '''    static func makeStateStore() -> SyncStateStore {
        let base = URL(filePath: ProcessInfo.processInfo.environment["SYNCCHECK_STATE"] ?? "/nonexistent", directoryHint: .isDirectory)
        return SyncStateStore(supportDirectory: base.appending(path: "Support"), cachesDirectory: base.appending(path: "Caches"))
    }

''' + text[end:]
open(path, "w").write(text)
PYTHON

cat > "$work/AssetStubs.swift" <<'EOF'
import AppKit
import SwiftUI

// Stand-ins for the symbols Xcode generates from holzBar/Resources/Assets.xcassets.
extension ImageResource {
    static let appLogo = ImageResource(name: "AppLogo", bundle: .main)
    static let logoStroke = ImageResource(name: "LogoStroke", bundle: .main)
    static let warning = ImageResource(name: "Warning", bundle: .main)
}

extension ColorResource {
    static let defaultLayoutBar = ColorResource(name: "DefaultLayoutBarColor", bundle: .main)
}

extension Color {
    static let defaultLayoutBar = Color(.defaultLayoutBar)
}

extension NSImage {
    static let warning = NSImage(resource: .warning)
}
EOF

# A command-line program has no bundle identifier; this one gets one of its own, so it never reads or writes the
# preferences of holzBar.
cat > "$work/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.holzcloud.holzBar.synccheck</string>
<key>CFBundleName</key><string>synccheck</string>
</dict></plist>
EOF

cat > "$work/Check.swift" <<'EOF'
import AppKit
import Foundation

@main
struct SyncAppCheck {
    /// Reports a failed expectation and ends the program.
    @MainActor
    static func expect(_ condition: Bool, _ what: String) {
        if !condition {
            print("FAILED: \(what)")
            exit(1)
        }
    }

    @MainActor
    static func spin(_ seconds: Double, until condition: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        let command = arguments[1]
        if command == "normalizers" {
            normalizers()
            return
        }
        let folder = URL(filePath: arguments[2], directoryHint: .isDirectory)
        setenv("SYNCCHECK_STATE", arguments[3], 1)
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier ?? ""
        expect(domain == "com.holzcloud.holzBar.synccheck", "the check runs in its own preferences domain")

        switch command {
        case "reset":
            defaults.removePersistentDomain(forName: domain)
        case "prepare-a", "prepare-b":
            defaults.removePersistentDomain(forName: domain)
            defaults.set(true, forKey: "SyncsSettingsWithICloud")
            if command == "prepare-a" {
                defaults.set(true, forKey: "ShowOnHover")
            }
            defaults.set(try? folder.bookmarkData(), forKey: "SettingsSyncFolderBookmark")
            defaults.set("3F2504E0-4F89-11D3-9A0C-0305E82C3301", forKey: "SettingsSyncDeviceID")
            defaults.set(Date(timeIntervalSinceReferenceDate: 650_000_000), forKey: "SettingsSyncLastSynced")
            defaults.set("old-digest", forKey: "SettingsSyncBaseSettingsDigest")
            defaults.set(3, forKey: "SettingsSyncLayoutEdits")
            defaults.synchronize()
        case "found":
            found(folder, arguments[3])
        case "join":
            join(folder, arguments[3])
        case "apply":
            apply(folder)
        case "conflict":
            conflict(folder, arguments[3])
        case "edit":
            edit(folder, arguments[3])
        default:
            expect(false, "unknown command \(command)")
        }
    }

    // MARK: The app

    /// What the app does at its start: the launch before anything reads the settings, then the setup.
    @MainActor
    static func start(setup: Bool = true) -> (host: SettingsSync, appState: AppState) {
        SettingsSync.launch()
        let host = SettingsSync.forAppState()
        _ = NSApplication.shared
        let appState = AppState()
        if setup {
            host.performSetup(with: appState)
        }
        return (host, appState)
    }

    static func deviceFiles(_ folder: URL) -> [String] {
        let macs = folder.appending(path: "holzBar/Macs", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(atPath: macs.path(percentEncoded: false))) ?? []).filter { $0.hasSuffix(".plist") }.sorted()
    }

    static func quit(_ host: SettingsSync) -> Never {
        host.prepareForTermination()
        exit(0)
    }

    // MARK: Scenarios

    @MainActor
    static func found(_ folder: URL, _ state: String) {
        let defaults = UserDefaults.standard
        let bookkeeping = ["SettingsSyncLastSynced", "SettingsSyncBaseSettingsDigest", "SettingsSyncLayoutEdits"]
        let before = bookkeeping.map { defaults.object(forKey: $0) as? NSObject }
        SettingsSync.launch()
        let host = SettingsSync.forAppState()
        expect(host.isEnabled, "sync is on after the launch")
        expect(host.view.lines == [.joining(waitingFiles: 0)], "the launch joins the folder: \(host.view.lines)")
        expect(defaults.string(forKey: "SettingsSyncLegacyDeviceID") == "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "the old ID is kept as the legacy ID")
        expect(defaults.string(forKey: "SettingsSyncDeviceID") != "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "the ID rotated once")
        expect(deviceFiles(folder).isEmpty, "the launch writes no file")
        _ = NSApplication.shared
        let appState = AppState()
        host.performSetup(with: appState)
        spin(15) { deviceFiles(folder).count == 1 && host.view.lines.isEmpty }
        expect(deviceFiles(folder).count == 1, "the group is founded with the own device file: \(deviceFiles(folder))")
        expect(host.view.lines.isEmpty && host.hint == nil, "the join is done and shows no hint: \(host.view)")
        expect(defaults.object(forKey: "ShowOnHover") as? Bool == true, "the Mac keeps its setting")
        expect(FileManager.default.fileExists(atPath: state + "/Support/holzBar/Sync/State.plist"), "the state file is written")
        expect(bookkeeping.map { defaults.object(forKey: $0) as? NSObject } == before, "the keys of the earlier builds are as they were")
        expect(host.folderDisplayName == folder.path(percentEncoded: false) || host.folderDisplayName?.hasSuffix(folder.lastPathComponent) == true, "the folder's name is shown")
        quit(host)
    }

    @MainActor
    static func join(_ folder: URL, _ state: String) {
        let defaults = UserDefaults.standard
        let (host, _) = start()
        spin(15) { host.hint != nil && deviceFiles(folder).count == 3 }
        expect(host.hint == .restart, "the joined Mac shows the Restart hint: \(String(describing: host.hint)) \(host.view.lines)")
        expect(defaults.object(forKey: "ShowOnHover") == nil, "the setting waits for the restart")
        expect(deviceFiles(folder).count == 3, "the joined Mac wrote its own file next to the two others: \(deviceFiles(folder))")
        quit(host)
    }

    @MainActor
    static func apply(_ folder: URL) {
        // The launch applies what the group holds, before anything reads the settings.
        SettingsSync.launch()
        let host = SettingsSync.forAppState()
        expect(UserDefaults.standard.object(forKey: "ShowOnHover") as? Bool == false, "the launch applies the first Mac's setting")
        expect(host.hint == nil, "nothing waits any more: \(String(describing: host.hint))")
        quit(host)
    }

    @MainActor
    static func conflict(_ folder: URL, _ state: String) {
        let defaults = UserDefaults.standard
        let (host, _) = start()
        spin(2)
        // Another Mac writes its file with another value of the setting.
        let other = SyncMacID(UUID())
        let entry = SyncEntry(dot: SyncDot(mac: other, n: 5), at: Date(), payload: .value(.bool(false)))
        let replica = SyncReplica(context: SyncContext(counters: [other: 5]), registers: [.whole("ShowOnHover"): [entry]])
        let contents = SyncDeviceFile.Contents(unitTable: 1, mac: other, installation: "other", written: Date(), replica: replica)
        let written = SyncFolderWriter.write(contents, syncFolder: folder, expecting: .absent)
        guard case .verified = written else {
            expect(false, "the other Mac's file was written: \(written)")
            return
        }
        spin(15) { host.hint != nil }
        expect(host.hint == .choose, "the arrival of the file is heard and asks: \(String(describing: host.hint))")
        guard let question = host.currentQuestion() else {
            expect(false, "there is a question")
            return
        }
        expect(question.rows.count == 1, "the question has one row")
        expect(defaults.object(forKey: "ShowOnHover") as? Bool == true, "nothing is applied before the answer")
        host.submit(SyncAnswerRequest(button: .keep, question: question))
        spin(15) { host.hint == nil }
        expect(host.hint == nil, "Keep ends the question: \(String(describing: host.hint))")
        expect(defaults.object(forKey: "ShowOnHover") as? Bool == true, "Keep keeps this Mac's value")
        quit(host)
    }

    @MainActor
    static func edit(_ folder: URL, _ state: String) {
        let defaults = UserDefaults.standard
        let (host, _) = start()
        spin(2)
        guard let name = deviceFiles(folder).first else {
            expect(false, "the Mac has its device file")
            return
        }
        let url = folder.appending(path: "holzBar/Macs/\(name)")
        let before = try? Data(contentsOf: url)
        defaults.set(false, forKey: "ShowOnHover")
        spin(15) { (try? Data(contentsOf: url)) != before }
        expect((try? Data(contentsOf: url)) != before, "the change is captured and written to the own file")
        quit(host)
    }

    // MARK: Normalizers

    @MainActor
    static func normalizers() {
        var failures: [String] = []
        func check(_ condition: Bool, _ what: String) {
            if !condition {
                failures.append(what)
            }
        }
        precondition(Thread.isMainThread, "the check runs on the main thread")

        let normalizers = SyncModelNormalizers.make()
        let encoder = JSONEncoder()

        // The appearance: the default configuration is applicable, canonical, and stays so.
        if let data = try? encoder.encode(MenuBarAppearanceConfigurationV2.defaultConfiguration) {
            let once = normalizers.appearance(.data(data))
            check(once != nil, "the default appearance is applicable")
            check(once.flatMap(normalizers.appearance) == once, "the appearance normalizes to itself")
            if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var unknown = raw
                unknown["aFieldOfANewerBuild"] = true
                if let changed = try? JSONSerialization.data(withJSONObject: unknown) {
                    check(normalizers.appearance(.data(changed)) == nil, "an appearance with an unknown field is not applicable")
                }
            }
        } else {
            check(false, "the default appearance encodes")
        }
        check(normalizers.appearance(.data(Data("not json".utf8))) == nil, "an appearance that is no JSON is not applicable")
        check(normalizers.appearance(.string("text")) == nil, "an appearance that is no data is not applicable")

        // The item groups: no group, and a value that is no list.
        check(normalizers.itemGroups(.data(Data("[]".utf8))) != nil, "an empty list of groups is applicable")
        check(normalizers.itemGroups(.data(Data("{\"a\":1}".utf8))) == nil, "a dictionary is not a list of groups")

        // The holzBar icon: the default image set with the template flag.
        if let set = try? encoder.encode(ControlItemImageSet.defaultHolzBarIcon) {
            let icon = SyncValue.dictionary([SyncNormalizers.iconField: .data(set), SyncNormalizers.templateField: .bool(true)])
            let once = normalizers.holzBarIcon(icon)
            check(once != nil, "the default icon is applicable")
            check(once.flatMap(normalizers.holzBarIcon) == once, "the icon normalizes to itself")
        } else {
            check(false, "the default image set encodes")
        }
        check(normalizers.holzBarIcon(.dictionary([:])) == nil, "an empty icon is not applicable")

        if failures.isEmpty {
            print("==> The sync normalizers ran on the main actor")
        } else {
            for failure in failures {
                print("FAILED: \(failure)")
            }
            exit(1)
        }
    }
}
EOF

files=()
while IFS= read -r file; do
    files+=("$file")
done < <(find "$work/src" -name '*.swift' | sort)
files+=("$work/AssetStubs.swift" "$work/Check.swift")

if ! swiftc -wmo -o "$work/check" \
    -parse-as-library \
    -module-name holzBar \
    -target arm64-apple-macos14.0 \
    -sdk "$sdk" \
    -swift-version 6 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$work/Info.plist" \
    "${files[@]}" > "$work/build.log" 2>&1; then
    grep -E "error" "$work/build.log" | head -20
    exit 1
fi

"$work/check" normalizers

# Mac A and Mac B, each with a state folder of its own, one after another in one sync folder.
run() {
    echo "-- $*"
    "$work/check" "$1" "$work/folder" "$work/state-$2"
}

run prepare-a a
run found a
run conflict a
run edit a
run prepare-b b
run join b
run apply b

echo "==> The sync host ran as two Macs on real files"
