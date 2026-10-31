//
//  NowPlayingPayloadTests.swift
//  holzBarTests
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("NowPlayingPayload")
struct NowPlayingPayloadTests {
    private let music = NowPlayingPayload.musicNotification
    private let spotify = NowPlayingPayload.spotifyNotification

    private func musicInfo(_ overrides: [String: Any] = [:]) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Some Song",
            "Artist": "Some Artist",
            "Album": "Some Album",
            "Total Time": 215_000,
            "Location": "file:///Users/x/Music/a.m4a",
        ]
        for (key, value) in overrides {
            info[key] = value
        }
        return info
    }

    // MARK: Music

    @Test("A full Music payload parses to its texts, duration and file")
    func fullMusicPayload() throws {
        let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo()))
        #expect(event.player == .music)
        #expect(event.state == .playing)
        #expect(event.track?.title == "Some Song")
        #expect(event.track?.artist == "Some Artist")
        #expect(event.track?.album == "Some Album")
        #expect(event.track?.duration == 215)
        #expect(event.track?.fileURL == URL(string: "file:///Users/x/Music/a.m4a"))
        #expect(event.position == nil)
    }

    @Test("A payload without a state, or with an unknown one, is ignored")
    func missingOrUnknownState() {
        var noState = musicInfo()
        noState["Player State"] = nil
        #expect(NowPlayingPayload.parse(name: music, userInfo: noState) == nil)
        #expect(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Player State": "Buffering"])) == nil)
        #expect(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Player State": 3])) == nil)
        #expect(NowPlayingPayload.parse(name: music, userInfo: [:]) == nil)
    }

    @Test("The state is read case-insensitively")
    func stateIgnoresCase() {
        #expect(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Player State": "PAUSED"]))?.state == .paused)
        #expect(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Player State": " stopped "]))?.state == .stopped)
    }

    @Test("An unknown notification name gives nothing")
    func unknownName() {
        #expect(NowPlayingPayload.parse(name: "com.example.playerInfo", userInfo: musicInfo()) == nil)
        #expect(NowPlayingPayload.parse(name: "", userInfo: musicInfo()) == nil)
    }

    @Test("A location that is not a file URL is dropped and the rest of the event stays")
    func nonFileLocation() throws {
        for location in ["https://example.com/a.mp3", "/Users/x/Music/a.m4a", "not a url", "ftp://host/a.mp3"] {
            let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Location": location])))
            #expect(event.track?.fileURL == nil)
            #expect(event.track?.title == "Some Song")
        }
        let huge = "file:///" + String(repeating: "a", count: NowPlayingPayload.maxLocationLength + 1)
        let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Location": huge])))
        #expect(event.track?.fileURL == nil)
    }

    @Test("Text is trimmed, an empty string is unknown and a long text is cut")
    func textRules() throws {
        let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo([
            "Name": "  Padded \n", "Artist": "   ", "Album": String(repeating: "x", count: 600),
        ])))
        #expect(event.track?.title == "Padded")
        #expect(event.track?.artist == nil)
        #expect(event.track?.album?.count == NowPlayingPayload.maxTextLength)
        let wrongType = NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Name": 42]))
        #expect(wrongType?.track?.title == nil)
    }

    @Test("A duration of 0, a negative one, NaN, infinity or more than a day is unknown")
    func durationRange() throws {
        for bad: Any in [0, -5, Double.nan, Double.infinity, 90_000_000, "abc", [1]] {
            let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Total Time": bad])))
            #expect(event.track?.duration == nil)
        }
        let edge = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Total Time": 86_400_000])))
        #expect(edge.track?.duration == 86_400)
    }

    @Test("Int, Double, NSNumber and numeric String all give the same duration")
    func numbersOfEveryKind() throws {
        let values: [Any] = [215_000, 215_000.0, Float(215_000), NSNumber(value: 215_000), "215000", " 215000 "]
        for value in values {
            let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Total Time": value])))
            #expect(event.track?.duration == 215)
        }
    }

    @Test("A stopped payload with no track gives a stopped event with no track")
    func stoppedWithoutTrack() throws {
        let event = try #require(NowPlayingPayload.parse(name: music, userInfo: ["Player State": "Stopped"]))
        #expect(event.state == .stopped)
        #expect(event.track == nil)
        #expect(event.position == nil)
    }

    @Test("The persistent ID is the track's id, cut at 200 characters")
    func musicID() throws {
        let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Persistent ID": "ABCDEF"])))
        #expect(event.track?.id == "ABCDEF")
        let long = String(repeating: "z", count: 300)
        let cut = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Persistent ID": long])))
        #expect(cut.track?.id?.count == NowPlayingPayload.maxIDLength)
        let number = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Persistent ID": 12345])))
        #expect(number.track?.id == "12345")
    }

    @Test("Music reports no position, even if the payload carries a key of that name")
    func musicHasNoPosition() throws {
        let event = try #require(NowPlayingPayload.parse(name: music, userInfo: musicInfo(["Playback Position": 3.0])))
        #expect(event.position == nil)
    }

    // MARK: Spotify

    private func spotifyInfo(_ overrides: [String: Any] = [:]) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Another Song",
            "Artist": "Another Artist",
            "Album": "Another Album",
            "Duration": 215_000,
            "Playback Position": 12.5,
            "Track ID": "spotify:track:xyz",
        ]
        for (key, value) in overrides {
            info[key] = value
        }
        return info
    }

    @Test("A full Spotify payload parses to its texts, duration, position and id, and has no file")
    func fullSpotifyPayload() throws {
        let event = try #require(NowPlayingPayload.parse(name: spotify, userInfo: spotifyInfo(["Location": "file:///x.mp3"])))
        #expect(event.player == .spotify)
        #expect(event.state == .playing)
        #expect(event.track?.title == "Another Song")
        #expect(event.track?.artist == "Another Artist")
        #expect(event.track?.album == "Another Album")
        #expect(event.track?.duration == 215)
        #expect(event.track?.id == "spotify:track:xyz")
        #expect(event.track?.fileURL == nil)
        #expect(event.position == 12.5)
    }

    @Test("A negative, NaN or infinite Spotify position is unknown")
    func spotifyPositionRange() throws {
        for bad: Any in [-1.0, Double.nan, Double.infinity, "abc"] {
            let event = try #require(NowPlayingPayload.parse(name: spotify, userInfo: spotifyInfo(["Playback Position": bad])))
            #expect(event.position == nil)
            #expect(event.track?.title == "Another Song")
        }
        let zero = try #require(NowPlayingPayload.parse(name: spotify, userInfo: spotifyInfo(["Playback Position": 0])))
        #expect(zero.position == 0)
    }

    @Test("A Spotify payload without a state is ignored, and Music's keys do not count for Spotify")
    func spotifyNeedsItsOwnKeys() throws {
        var noState = spotifyInfo()
        noState["Player State"] = nil
        #expect(NowPlayingPayload.parse(name: spotify, userInfo: noState) == nil)
        let event = try #require(NowPlayingPayload.parse(name: spotify, userInfo: musicInfo()))
        #expect(event.player == .spotify)
        #expect(event.track?.duration == nil)
    }

    // MARK: Track and player values

    @Test("A track's identity is its id, else its four fields joined")
    func trackIdentity() {
        let withID = NowPlayingTrack(title: "A", artist: "B", id: "x1")
        let sameID = NowPlayingTrack(title: "Other", artist: "Other", id: "x1")
        #expect(withID.identity == sameID.identity)
        let plain = NowPlayingTrack(title: "A", artist: "B", album: "C", duration: 10)
        let same = NowPlayingTrack(title: "A", artist: "B", album: "C", duration: 10)
        let other = NowPlayingTrack(title: "A", artist: "B", album: "C", duration: 11)
        #expect(plain.identity == same.identity)
        #expect(plain.identity != other.identity)
        #expect(plain.identity != withID.identity)
    }

    @Test("The players hold their bundle identifiers and compare by them")
    func playerValues() {
        #expect(NowPlayingPlayer.music.bundleIdentifier == "com.apple.Music")
        #expect(NowPlayingPlayer.spotify.bundleIdentifier == "com.spotify.client")
        let other = NowPlayingPlayer(bundleIdentifier: "com.apple.Music")
        #expect(other == .music)
        #expect(other.hashValue == NowPlayingPlayer.music.hashValue)
        #expect(Set([NowPlayingPlayer.music, other, .spotify]).count == 2)
    }
}
