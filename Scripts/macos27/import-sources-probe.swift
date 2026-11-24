// How do Thaw and Hidden Bar store their settings on this Mac? Read-only: it reads two apps'
// preferences domains through UserDefaults and, with --file, one property list that you name.
// It prints the kind of every value, never a string, data, array or dictionary value; Boolean
// and number values only with --values. It writes no file, starts no process, opens no connection
// and never opens a folder under ~/Library/Containers by itself.
//
// Run it on a Mac that has run Thaw and Hidden Bar:
//
//   swift Scripts/macos27/import-sources-probe.swift 2>&1 | tee ~/Desktop/import-sources.txt
//   swift Scripts/macos27/import-sources-probe.swift --values 2>&1 | tee ~/Desktop/import-sources-values.txt
//
// The App Store build of Hidden Bar keeps its preferences inside its container, which a plain
// read of its domain does not reach. If the first run says its domain is empty although the app
// is installed, copy the property list out of the container yourself and name the copy:
//
//   swift Scripts/macos27/import-sources-probe.swift --file ~/Desktop/com.dwarvesv.minimalbar.plist
//
// What a run does, for each source (Thaw: com.stonerl.Thaw, Hidden Bar: com.dwarvesv.minimalbar):
//   1. Says whether the app is installed (where macOS finds it by its bundle identifier).
//   2. Says how many keys its preferences domain holds, or that it is empty.
//   3. Lists every key, sorted, with the kind of its value: Bool, integer, real, string (its
//      length), data (its byte count), array (its count), dictionary (its key count) or date.
//
// Options:
//   --file <path>   read this one property list instead (a regular file, at most 8 MB) and list
//                   it the same way
//   --values        also print the value of the Boolean and number keys
//   --help
import AppKit
import Foundation

// MARK: - Options

struct Options {
    var file: String?
    var values = false
}

struct Source {
    let name: String
    let bundleIdentifier: String
}

let sources = [
    Source(name: "Thaw", bundleIdentifier: "com.stonerl.Thaw"),
    Source(name: "Hidden Bar", bundleIdentifier: "com.dwarvesv.minimalbar"),
]

let maxFileSize = 8 * 1024 * 1024

func parseOptions() -> Options {
    var parsed = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--file":
            guard let value = arguments.first else {
                print("--file needs a path, see --help")
                exit(64)
            }
            parsed.file = value
            arguments.removeFirst()
        case "--values":
            parsed.values = true
        case "--help", "-h":
            print("usage: swift import-sources-probe.swift [--file PATH] [--values]")
            exit(0)
        default:
            print("unknown option \(argument), see --help")
            exit(64)
        }
    }
    return parsed
}

func out(_ line: String) {
    print(line)
}

// MARK: - Listing

/// The kind of a value, and its Boolean or number when `showValues` is on. Never a text, data,
/// array or dictionary value.
func describe(_ value: Any, showValues: Bool) -> String {
    let object = value as CFTypeRef
    let type = CFGetTypeID(object)
    if type == CFBooleanGetTypeID() {
        // swiftlint:disable:next force_cast
        let flag = CFBooleanGetValue((object as! CFBoolean))
        return "Bool" + (showValues ? " \(flag)" : "")
    }
    if type == CFNumberGetTypeID() {
        // swiftlint:disable:next force_cast
        let isReal = CFNumberIsFloatType((object as! CFNumber))
        return (isReal ? "real" : "integer") + (showValues ? " \(object)" : "")
    }
    if let text = value as? String {
        return "string (length \(text.count))"
    }
    if let data = value as? Data {
        return "data (\(data.count) bytes)"
    }
    if let array = value as? [Any] {
        return "array (\(array.count))"
    }
    if let dictionary = value as? [String: Any] {
        return "dictionary (\(dictionary.count) keys)"
    }
    if value is Date {
        return "date"
    }
    return "other"
}

func list(_ settings: [String: Any], showValues: Bool) {
    for key in settings.keys.sorted() {
        out("    \(key) = \(describe(settings[key] as Any, showValues: showValues))")
    }
}

func report(_ source: Source, showValues: Bool) {
    out("SOURCE \(source.name) (\(source.bundleIdentifier))")
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) {
        out("  installed: yes, \(url.path)")
    } else {
        out("  installed: no")
    }
    guard let domain = UserDefaults.standard.persistentDomain(forName: source.bundleIdentifier), !domain.isEmpty else {
        out("  preferences domain: empty")
        out("import-sources-probe \(source.name) installed=\(NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil) keys=0")
        return
    }
    out("  preferences domain: \(domain.count) keys")
    list(domain, showValues: showValues)
    out("import-sources-probe \(source.name) installed=\(NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil) keys=\(domain.count)")
}

func reportFile(_ path: String, showValues: Bool) {
    let expanded = (path as NSString).expandingTildeInPath
    out("FILE \(expanded)")
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: expanded) else {
        out("  not readable: no such file")
        exit(1)
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
        out("  refused: not a regular file (a folder, a link or something else)")
        exit(1)
    }
    let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
    guard size <= maxFileSize else {
        out("  refused: \(size) bytes is more than the limit of \(maxFileSize) bytes")
        exit(1)
    }
    guard let data = FileManager.default.contents(atPath: expanded) else {
        out("  not readable: the file could not be read")
        exit(1)
    }
    var format = PropertyListSerialization.PropertyListFormat.xml
    guard
        let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
        let settings = object as? [String: Any]
    else {
        out("  not a property list with a dictionary at its root")
        exit(1)
    }
    let formatName: String
    switch format {
    case .xml: formatName = "xml"
    case .binary: formatName = "binary"
    case .openStep: formatName = "openStep"
    @unknown default: formatName = "other"
    }
    out("  property list: \(formatName), \(size) bytes, \(settings.count) keys")
    list(settings, showValues: showValues)
    out("import-sources-probe file keys=\(settings.count)")
}

// MARK: - Main

let options = parseOptions()
setvbuf(stdout, nil, _IOLBF, 0)
out("import-sources-probe macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
if let path = options.file {
    reportFile(path, showValues: options.values)
} else {
    for source in sources {
        report(source, showValues: options.values)
    }
}
out("")
out("=== end of report ===")
