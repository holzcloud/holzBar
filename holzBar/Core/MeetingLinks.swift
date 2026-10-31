//
//  MeetingLinks.swift
//  holzBar
//

import Foundation

/// The service a meeting link belongs to.
nonisolated enum MeetingService: Equatable, Sendable {
    case zoom
    case googleMeet
    case teams
    case webex
    case faceTime
    /// An https link from the event's URL field or location whose host is not a known service.
    case other
}

/// A link that may be offered as a Join button: https, no credentials, a host.
nonisolated struct MeetingLink: Equatable, Sendable {
    let url: URL
    let service: MeetingService
}

/// Finds the meeting link of an event and decides when it can be joined.
///
/// A link in an invitation is written by someone else, so nothing but a validated `https`
/// link is ever offered: no other scheme, no user name or password in the URL, always a host.
/// A link in the free text of the notes is offered only on a known meeting host.
nonisolated enum MeetingLinks {
    /// How long before the start the Join button appears, in minutes.
    static let joinLeadMinutes = 10

    /// The same, in seconds.
    static var joinLeadSeconds: TimeInterval { TimeInterval(joinLeadMinutes * 60) }

    /// How much of the notes is searched, in characters.
    static let searchedNotesLength = 4_000

    /// How much of the location is searched, in characters.
    static let searchedLocationLength = 500

    /// The hosts of the known meeting services. A host matches itself and, where the entry
    /// begins with a dot, every subdomain of it.
    private static let knownHosts: [(host: String, service: MeetingService)] = [
        ("zoom.us", .zoom),
        (".zoom.us", .zoom),
        ("meet.google.com", .googleMeet),
        ("teams.microsoft.com", .teams),
        ("teams.live.com", .teams),
        ("webex.com", .webex),
        (".webex.com", .webex),
        ("facetime.apple.com", .faceTime),
    ]

    /// The meeting link of an event, if it has one.
    ///
    /// The places are searched in this order: the URL field, the location, the notes. A link
    /// from the URL field or the location is kept on any host (service ``MeetingService/other``
    /// for an unknown one); a link from the notes only on a known meeting host.
    static func find(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = validate(url.absoluteString, requiresKnownHost: false) {
            return link
        }
        if let location, let link = scan(String(location.prefix(searchedLocationLength)), requiresKnownHost: false) {
            return link
        }
        if let notes, let link = scan(String(notes.prefix(searchedNotesLength)), requiresKnownHost: true) {
            return link
        }
        return nil
    }

    /// Whether the Join button shows: from ``joinLeadMinutes`` before the start until the end.
    static func isJoinable(start: Date, end: Date, now: Date) -> Bool {
        now >= start.addingTimeInterval(-joinLeadSeconds) && now < max(start, end)
    }

    // MARK: Scanning

    /// The first valid https link in free text. The scan walks the text once, looking for
    /// `https://` without regard to case.
    private static func scan(_ text: String, requiresKnownHost: Bool) -> MeetingLink? {
        var search = text.startIndex..<text.endIndex
        while let found = text.range(of: "https://", options: .caseInsensitive, range: search) {
            var end = found.upperBound
            while end < text.endIndex, !isTerminator(text[end]) {
                end = text.index(after: end)
            }
            if let link = validate(trimmed(String(text[found.lowerBound..<end])), requiresKnownHost: requiresKnownHost) {
                return link
            }
            search = found.upperBound..<text.endIndex
        }
        return nil
    }

    /// Whether a character ends a link in running text: white space and the characters that
    /// wrap links in angle brackets or quotes.
    private static func isTerminator(_ character: Character) -> Bool {
        character.isWhitespace || "<>\"'`|\\^{}".contains(character)
    }

    /// Removes the punctuation that follows a link in a sentence.
    private static func trimmed(_ candidate: String) -> String {
        var result = Substring(candidate)
        while let last = result.last, ".,;:!?)]>".contains(last) {
            result = result.dropLast()
        }
        return String(result)
    }

    // MARK: Validation

    /// The link for a candidate, or `nil` when it is not https, has a user name or password,
    /// has no host, or is not on a known host where that is required.
    private static func validate(_ candidate: String, requiresKnownHost: Bool) -> MeetingLink? {
        guard !candidate.isEmpty,
              let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        if let service = service(forHost: host) {
            return MeetingLink(url: url, service: service)
        }
        return requiresKnownHost ? nil : MeetingLink(url: url, service: .other)
    }

    private static func service(forHost host: String) -> MeetingService? {
        for entry in knownHosts {
            if entry.host.hasPrefix(".") {
                if host.hasSuffix(entry.host) { return entry.service }
            } else if host == entry.host {
                return entry.service
            }
        }
        return nil
    }
}
