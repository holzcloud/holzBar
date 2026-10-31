//
//  DatabaseAccess.swift
//  notifications
//
//  ROUTE-B: can the notification database be opened without Full Disk Access? The probe
//  opens each candidate path for reading only and closes the descriptor at once. It never
//  reads, maps or parses a byte, so it cannot disclose a notification even when the open
//  succeeds.
//

import Darwin
import Foundation
import NotificationProbeCore

enum DatabaseAccess {
    struct Candidate {
        let name: String
        let path: String
    }

    /// The two places the database has lived: the group container of `usernoted`, and the
    /// per-user temporary directory of the notification center.
    static func candidates() -> [Candidate] {
        var result = [
            Candidate(
                name: "groupContainer",
                path: NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
            ),
        ]
        if let directory = darwinUserDirectory() {
            result.append(Candidate(name: "darwinUserDir", path: directory + "com.apple.notificationcenter/db2/db"))
        }
        return result
    }

    /// Opens the path read-only and closes it again; nothing is taken from it.
    static func probe(_ path: String) -> DatabaseOutcome {
        let descriptor = open(path, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return .ok
        }
        return DatabaseOutcome.fromErrno(errno)
    }

    /// Runs the check and writes one DB line per candidate; returns the outcomes.
    static func run() -> [DatabaseOutcome] {
        let candidates = candidates()
        var outcomes = [DatabaseOutcome]()
        for candidate in candidates {
            let outcome = probe(candidate.path)
            outcomes.append(outcome)
            Out.emit(ProbeLine.line("DB", [("candidate", candidate.name), ("access", outcome.word)]))
        }
        // The directory of the second candidate could not be asked for.
        if candidates.count < 2 {
            Out.emit(ProbeLine.line("DB", [("candidate", "darwinUserDir"), ("access", "absent")]))
            outcomes.append(.absent)
        }
        return outcomes
    }

    /// The per-user temporary directory, with its trailing slash (`getconf DARWIN_USER_DIR`).
    private static func darwinUserDirectory() -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 else {
            return nil
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
