import Foundation
import Testing
@testable import HolzBarCore

@Suite("MeetingLinks")
struct MeetingLinksTests {
    private func link(url: String? = nil, location: String? = nil, notes: String? = nil) -> MeetingLink? {
        MeetingLinks.find(url: url.flatMap { URL(string: $0) }, location: location, notes: notes)
    }

    @Test("Each known service is recognised in the URL field")
    func knownServices() {
        let cases: [(String, MeetingService)] = [
            ("https://us02web.zoom.us/j/123456789?pwd=abc", .zoom),
            ("https://zoom.us/j/1", .zoom),
            ("https://meet.google.com/abc-defg-hij", .googleMeet),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting", .teams),
            ("https://teams.live.com/meet/9876", .teams),
            ("https://acme.webex.com/meet/jane", .webex),
            ("https://facetime.apple.com/join#v=1&p=x", .faceTime),
        ]
        for (text, service) in cases {
            let found = link(url: text)
            #expect(found?.service == service, "\(text)")
            #expect(found?.url.absoluteString == text)
        }
    }

    @Test("A known link inside notes text is found without the punctuation after it")
    func linkInNotes() {
        let notes = "Hello,\nJoin: https://meet.google.com/abc-defg-hij).\nSee you!"
        let found = link(notes: notes)
        #expect(found?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(found?.service == .googleMeet)
        #expect(link(notes: "<https://zoom.us/j/55>, thanks")?.url.absoluteString == "https://zoom.us/j/55")
        #expect(link(notes: "HTTPS://zoom.us/j/55")?.service == .zoom)
    }

    @Test("The order is URL field, location, notes")
    func order() {
        let found = link(
            url: "https://meet.google.com/aaa-bbbb-ccc",
            location: "https://zoom.us/j/2",
            notes: "https://acme.webex.com/meet/x"
        )
        #expect(found?.service == .googleMeet)
        #expect(link(location: "Room 4, https://zoom.us/j/2", notes: "https://meet.google.com/a")?.service == .zoom)
        #expect(link(notes: "Zoom: https://zoom.us/j/7 and Meet: https://meet.google.com/a")?.service == .zoom)
    }

    @Test("Only https is accepted, and never with a user name or password")
    func refusals() {
        let refused = [
            "http://zoom.us/j/1",
            "javascript:alert(1)",
            "file:///etc/hosts",
            "zoommtg://zoom.us/join?confno=1",
            "https://user:pw@zoom.us/j/1",
            "https://user@zoom.us/j/1",
            "https:///nohost",
            "ftp://example.com/x",
        ]
        for text in refused {
            #expect(link(url: text) == nil, "\(text)")
            #expect(link(location: text) == nil, "\(text)")
            #expect(link(notes: "Join at \(text) now") == nil, "\(text)")
        }
    }

    @Test("An unknown host counts as a plain link in the URL field or the location, not in the notes")
    func unknownHosts() {
        #expect(link(url: "https://meet.example.org/room/7")?.service == .other)
        #expect(link(location: "https://video.example.org/r/9")?.service == .other)
        #expect(link(notes: "https://video.example.org/r/9") == nil)
        #expect(link(url: "https://notzoom.us/j/1")?.service == .other)
        #expect(link(url: "https://zoom.us.evil.example/j/1")?.service == .other)
    }

    @Test("Only the first 4000 characters of the notes are searched; empty and nil give nothing")
    func limitsAndEmptyInput() {
        let filler = String(repeating: "x ", count: 2_000)
        #expect(link(notes: filler + "https://zoom.us/j/1") == nil)
        #expect(link(notes: String(repeating: "x ", count: 1_000) + "https://zoom.us/j/1")?.service == .zoom)
        #expect(link() == nil)
        #expect(link(url: "", location: "", notes: "") == nil)
        #expect(MeetingLinks.find(url: nil, location: nil, notes: nil) == nil)
        #expect(link(notes: "https://") == nil)
        #expect(link(notes: "no link here, only https:// and words") == nil)
    }

    @Test("A link is joinable from ten minutes before the start until the end")
    func joinWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3_600)
        #expect(MeetingLinks.joinLeadMinutes == 10)
        #expect(!MeetingLinks.isJoinable(start: start, end: end, now: start.addingTimeInterval(-11 * 60)))
        #expect(MeetingLinks.isJoinable(start: start, end: end, now: start.addingTimeInterval(-10 * 60)))
        #expect(MeetingLinks.isJoinable(start: start, end: end, now: start))
        #expect(MeetingLinks.isJoinable(start: start, end: end, now: end.addingTimeInterval(-1)))
        #expect(!MeetingLinks.isJoinable(start: start, end: end, now: end))
        #expect(!MeetingLinks.isJoinable(start: start, end: end, now: end.addingTimeInterval(60)))
    }
}
