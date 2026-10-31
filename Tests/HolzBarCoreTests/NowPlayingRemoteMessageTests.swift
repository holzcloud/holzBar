//
//  NowPlayingRemoteMessageTests.swift
//  holzBarTests
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("NowPlayingRemoteMessage")
struct NowPlayingRemoteMessageTests {
    /// 2024-11-02 00:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_730_505_600)

    /// The seconds since 1970 of `now`, minus an offset.
    private func at(minus seconds: Double) -> String {
        String(now.timeIntervalSince1970 - seconds)
    }

    private func event(_ line: String) -> NowPlayingEvent? {
        if case .event(let event) = NowPlayingRemoteMessage.parse(line: line, now: now) {
            return event
        }
        return nil
    }

    // MARK: A playing line

    @Test("A playing line parses to the app, the texts, the duration and a position that moved on")
    func playingLine() throws {
        let line = """
        {"v":1,"bundle":"com.apple.Safari","playing":true,"title":"A Title","artist":"An Artist",\
        "album":"An Album","duration":215.0,"elapsed":12.5,"rate":1.0,"at":\(at(minus: 2))}
        """
        let parsed = try #require(event(line))
        #expect(parsed.player == NowPlayingPlayer(bundleIdentifier: "com.apple.Safari"))
        #expect(parsed.state == .playing)
        #expect(parsed.track?.title == "A Title")
        #expect(parsed.track?.artist == "An Artist")
        #expect(parsed.track?.album == "An Album")
        #expect(parsed.track?.duration == 215)
        #expect(parsed.track?.fileURL == nil)
        #expect(parsed.track?.id == nil)
        let position = try #require(parsed.position)
        #expect(abs(position - 14.5) < 0.001)
    }

    @Test("A paused line keeps its position, and so does a rate of 0 or a missing rate")
    func positionDoesNotAdvance() throws {
        let paused = """
        {"v":1,"bundle":"a.b","playing":false,"title":"T","elapsed":12.5,"rate":1.0,"at":\(at(minus: 2))}
        """
        #expect(event(paused)?.position == 12.5)
        #expect(event(paused)?.state == .paused)
        let stalled = """
        {"v":1,"bundle":"a.b","playing":true,"title":"T","elapsed":12.5,"rate":0,"at":\(at(minus: 2))}
        """
        #expect(event(stalled)?.position == 12.5)
        let noRate = """
        {"v":1,"bundle":"a.b","playing":true,"title":"T","elapsed":12.5,"at":\(at(minus: 2))}
        """
        #expect(event(noRate)?.position == 12.5)
        let noTimestamp = #"{"v":1,"bundle":"a.b","playing":true,"title":"T","elapsed":12.5,"rate":1}"#
        #expect(event(noTimestamp)?.position == 12.5)
    }

    @Test("A position never exceeds the duration or goes below 0, and a bad elapsed time is unknown")
    func positionIsBounded() throws {
        let past = #"{"v":1,"bundle":"a.b","playing":true,"title":"T","duration":100,"elapsed":99,"rate":1,"at":\#(at(minus: 50))}"#
        #expect(event(past)?.position == 100)
        let over = #"{"v":1,"bundle":"a.b","playing":false,"title":"T","duration":100,"elapsed":500}"#
        #expect(event(over)?.position == 100)
        let future = #"{"v":1,"bundle":"a.b","playing":true,"title":"T","elapsed":5,"rate":1,"at":\#(at(minus: -30))}"#
        #expect(event(future)?.position == 5)
        for bad in ["-3", "\"nan\"", "1e999", "null", "true"] {
            let line = #"{"v":1,"bundle":"a.b","playing":false,"title":"T","elapsed":\#(bad)}"#
            #expect(event(line)?.position == nil, "elapsed \(bad)")
        }
    }

    // MARK: None and errors

    @Test("None, and every named error, parse; an unknown error text is invalid")
    func noneAndErrors() {
        #expect(NowPlayingRemoteMessage.parse(line: #"{"v":1,"none":true}"#, now: now) == .none)
        for failure in ["framework", "symbol", "unavailable", "timeout"] {
            let result = NowPlayingRemoteMessage.parse(line: #"{"v":1,"error":"\#(failure)"}"#, now: now)
            #expect(result == .unavailable(NowPlayingRemoteMessage.Failure(rawValue: failure)!), "error \(failure)")
        }
        #expect(NowPlayingRemoteMessage.parse(line: #"{"v":1,"error":"boom"}"#, now: now) == .invalid)
        #expect(NowPlayingRemoteMessage.parse(line: #"{"v":1,"error":3}"#, now: now) == .invalid)
        #expect(NowPlayingRemoteMessage.parse(line: #"{"v":1,"none":false}"#, now: now) == .invalid)
    }

    // MARK: Invalid lines

    @Test("Anything that is not a version 1 object with a valid bundle is invalid and never traps")
    func invalidLines() {
        let invalid = [
            "",
            "not json",
            "[1,2,3]",
            "\"text\"",
            "42",
            "{",
            #"{"v":1}"#,
            #"{"v":1,"bundle":""}"#,
            #"{"v":1,"bundle":7}"#,
            #"{"v":1,"bundle":"has space"}"#,
            #"{"v":1,"bundle":"semi;colon"}"#,
            #"{"v":1,"bundle":"ümlaut.app"}"#,
            #"{"v":1,"bundle":"new\nline"}"#,
            #"{"v":2,"bundle":"a.b","playing":true}"#,
            #"{"bundle":"a.b","playing":true}"#,
            #"{"v":"x","bundle":"a.b"}"#,
            #"{"v":1,"bundle":"\#(String(repeating: "a", count: 201))"}"#,
        ]
        for line in invalid {
            #expect(NowPlayingRemoteMessage.parse(line: line, now: now) == .invalid, "line \(line)")
        }
        let longest = String(repeating: "a", count: 200)
        #expect(event(#"{"v":1,"bundle":"\#(longest)","playing":true,"title":"T"}"#) != nil)
    }

    @Test("A line longer than 64 KB is invalid, one at the limit is not")
    func lineLimit() {
        let prefix = #"{"v":1,"bundle":"a.b","playing":true,"title":"T","pad":""#
        let suffix = #""}"#
        let room = NowPlayingRemoteMessage.maxLineBytes - prefix.utf8.count - suffix.utf8.count
        let atLimit = prefix + String(repeating: "x", count: room) + suffix
        #expect(atLimit.utf8.count == NowPlayingRemoteMessage.maxLineBytes)
        #expect(event(atLimit) != nil)
        let over = prefix + String(repeating: "x", count: room + 1) + suffix
        #expect(NowPlayingRemoteMessage.parse(line: over, now: now) == .invalid)
    }

    // MARK: Values

    @Test("Texts are trimmed and cut, an empty title is unknown, numbers may be strings, extra keys are ignored")
    func values() throws {
        let long = String(repeating: "y", count: 800)
        let line = """
        {"v":1,"bundle":"a.b","playing":true,"title":"  Padded  ","artist":"\(long)","album":"   ",\
        "duration":"215","elapsed":"10","rate":"1","at":"\(at(minus: 0))","extra":{"deep":[1,2]},"artwork":"nope"}
        """
        let parsed = try #require(event(line))
        #expect(parsed.track?.title == "Padded")
        #expect(parsed.track?.artist?.count == NowPlayingRemoteMessage.maxTextLength)
        #expect(parsed.track?.album == nil)
        #expect(parsed.track?.duration == 215)
        let position = try #require(parsed.position)
        #expect(abs(position - 10) < 0.001)
        let emptyTitle = #"{"v":1,"bundle":"a.b","playing":true,"title":""}"#
        #expect(event(emptyTitle)?.track?.title == nil)
    }

    @Test("A duration of 0, below 0 or above a day is unknown")
    func durations() {
        for bad in ["0", "-5", "86401", "1e999", "\"x\""] {
            let line = #"{"v":1,"bundle":"a.b","playing":true,"title":"T","duration":\#(bad)}"#
            #expect(event(line)?.track?.duration == nil, "duration \(bad)")
        }
        #expect(event(#"{"v":1,"bundle":"a.b","playing":true,"title":"T","duration":86400}"#)?.track?.duration == 86_400)
    }

    @Test("Playing without a title is playing, not playing with a title is paused, without one is stopped")
    func stateFromTitle() {
        let untitled = event(#"{"v":1,"bundle":"a.b","playing":true}"#)
        #expect(untitled?.state == .playing)
        #expect(untitled?.track == nil)
        #expect(event(#"{"v":1,"bundle":"a.b","playing":false,"title":"T"}"#)?.state == .paused)
        #expect(event(#"{"v":1,"bundle":"a.b","playing":false}"#)?.state == .stopped)
        #expect(event(#"{"v":1,"bundle":"a.b","title":"T"}"#)?.state == .paused)
        #expect(event(#"{"v":1,"bundle":"a.b","playing":1,"title":"T"}"#)?.state == .playing)
    }
}
