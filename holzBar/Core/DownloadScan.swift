//
//  DownloadScan.swift
//  holzBar
//

import Foundation

/// Which entries of a folder are downloads in progress, as a pure decision.
///
/// A browser that downloads a file leaves a mark in the folder until the download ends, when
/// the mark goes and the final name appears: Safari writes `Name.ext.download`, Chrome, Edge
/// and Brave `Name.ext.crdownload`, Firefox `Name.ext.part` and Opera `Name.ext.opdownload`.
/// The scan reads the names of the entries only, never what the files hold.
///
/// Rules:
/// 1. The last extension, compared without regard to case, must be one of the ``marks``; the
///    part before it is the final name.
/// 2. A name that starts with a dot is ignored: those are the browsers' temporary names.
/// 3. A mark without a final name gives nothing.
/// 4. A mark that is not the last extension (`notes.download.txt`) is not a download.
/// 5. A final name that is `Unconfirmed ` and digits (Chrome before it knows the name) is
///    flagged ``Partial/isUnnamed``.
/// 6. The result keeps the order of the input and lists each final name once.
nonisolated enum DownloadScan {
    /// The extensions that browsers give a file while it downloads, in lower case.
    static let marks: Set<String> = ["download", "crdownload", "part", "opdownload"]

    /// What Chrome calls a download before it knows the name.
    private static let unnamedPrefix = "Unconfirmed "

    /// A download in progress.
    nonisolated struct Partial: Equatable, Sendable {
        /// The mark, in lower case.
        let mark: String
        /// The name the file gets when the download ends.
        let finalName: String
        /// Whether the browser does not know the name yet.
        let isUnnamed: Bool
    }

    /// The downloads in progress among the entry names of a folder (its top level).
    static func partials(in names: [String]) -> [Partial] {
        var seen = Set<String>()
        var result = [Partial]()
        for name in names {
            guard let partial = partial(named: name), seen.insert(partial.finalName).inserted else {
                continue
            }
            result.append(partial)
        }
        return result
    }

    /// The download an entry name stands for, or `nil` when it is not a download in progress.
    private static func partial(named name: String) -> Partial? {
        guard !name.hasPrefix("."), let dot = name.lastIndex(of: ".") else {
            return nil
        }
        let mark = name[name.index(after: dot)...].lowercased()
        let finalName = String(name[..<dot])
        guard marks.contains(mark), !finalName.isEmpty else {
            return nil
        }
        return Partial(mark: mark, finalName: finalName, isUnnamed: isUnnamed(finalName))
    }

    /// Whether a name is `Unconfirmed ` followed by digits only.
    private static func isUnnamed(_ name: String) -> Bool {
        guard name.hasPrefix(unnamedPrefix) else {
            return false
        }
        let digits = name.dropFirst(unnamedPrefix.count)
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
