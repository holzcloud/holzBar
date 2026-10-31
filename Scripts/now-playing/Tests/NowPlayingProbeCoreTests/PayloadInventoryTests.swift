//
//  PayloadInventoryTests.swift
//  now-playing
//

import Foundation
import Testing
@testable import NowPlayingProbeCore

private func musicPayload() -> [String: Any] {
    [
        "Name": "Some Song",
        "Artist": "Some Artist",
        "Album": "Some Album",
        "Total Time": 215_000,
        "Player State": "Playing",
        "Persistent ID": "ABCDEF0123456789",
        "Location": "file:///Users/someone/Music/song.m4a",
    ]
}

private func spotifyPayload() -> [String: Any] {
    [
        "Name": "Another Song",
        "Artist": "Another Artist",
        "Album": "Another Album",
        "Duration": 180_000,
        "Playback Position": 12.5,
        "Player State": "Paused",
        "Track ID": "spotify:track:xyz",
    ]
}

@Test("The inventory lists every key with its value type, sorted by key")
func inventoryListsKeysAndTypes() {
    let entries = PayloadInventory.inventory([
        "b": "text", "a": 3, "c": 1.5, "d": true, "e": Date(timeIntervalSince1970: 0),
        "f": Data([1]), "g": [1, 2], "h": ["k": "v"], "i": URL(fileURLWithPath: "/"),
    ])
    #expect(entries.map(\.key) == ["a", "b", "c", "d", "e", "f", "g", "h", "i"])
    #expect(entries.map(\.type) == [
        "Int", "String", "Double", "Bool", "Date", "Data", "Array", "Dictionary", "Other",
    ])
}

@Test("A number that Foundation boxes keeps its kind: a boolean is a Bool, an integer an Int")
func inventoryTellsBoxedNumbersApart() {
    let entries = PayloadInventory.inventory([
        "flag": NSNumber(value: true), "count": NSNumber(value: 7), "ratio": NSNumber(value: 0.5),
    ])
    #expect(entries.map(\.key) == ["count", "flag", "ratio"])
    #expect(entries.map(\.type) == ["Int", "Bool", "Double"])
}

@Test("The flags find the keys of the Music and Spotify payloads, ignoring case")
func flagsFindCandidateKeys() {
    let music = PayloadInventory.flags(PayloadInventory.inventory(musicPayload()))
    #expect(music.hasName && music.hasArtist && music.hasAlbum && music.hasDuration)
    #expect(music.hasLocation && music.hasState)
    #expect(!music.hasPosition)

    let spotify = PayloadInventory.flags(PayloadInventory.inventory(spotifyPayload()))
    #expect(spotify.hasName && spotify.hasArtist && spotify.hasAlbum && spotify.hasDuration)
    #expect(spotify.hasPosition && spotify.hasState)
    #expect(!spotify.hasLocation)

    let shouting = PayloadInventory.flags(PayloadInventory.inventory(["NAME": "x", "player state": "Playing", "TOTAL TIME": 1]))
    #expect(shouting.hasName && shouting.hasState && shouting.hasDuration)
    #expect(!shouting.hasArtist)
}

@Test("A payload with other keys sets no flag")
func flagsStayFalseForUnknownKeys() {
    let flags = PayloadInventory.flags(PayloadInventory.inventory(["Foo": 1, "Bar": "x"]))
    #expect(flags == PayloadInventory.Flags())
}

@Test("A position is found under Playback Position, Player Position or Position")
func positionCandidates() {
    for key in ["Playback Position", "Player Position", "Position"] {
        let flags = PayloadInventory.flags(PayloadInventory.inventory([key: 1.0]))
        #expect(flags.hasPosition, "\(key) is a position")
    }
}

@Test("Redaction keeps only the length")
func redactionKeepsTheLength() {
    #expect(PayloadInventory.redacted("Some Song") == "len=9")
    #expect(PayloadInventory.redacted("") == "len=0")
}

@Test("The flags are written in the contract's order")
func flagsRenderInOrder() {
    let flags = PayloadInventory.flags(PayloadInventory.inventory(musicPayload()))
    #expect(flags.has == "name:y,artist:y,album:y,duration:y,position:n,location:y")
}

@Test("The keys of a payload are written as key:type pairs joined by semicolons")
func describeWritesKeyTypePairs() {
    let line = PayloadInventory.describe(PayloadInventory.inventory(spotifyPayload()))
    #expect(line == "Album:String;Artist:String;Duration:Int;Name:String;Playback Position:Double;Player State:String;Track ID:String")
}
