//
//  VerdictTests.swift
//  now-playing
//

import Testing
@testable import NowPlayingProbeCore

private func player(name: Bool = true, artist: Bool = true, duration: Bool = true, state: Bool = true) -> PlayerObservation {
    var observation = PlayerObservation()
    observation.record(PayloadInventory.Flags(
        hasName: name, hasArtist: artist, hasDuration: duration, hasState: state
    ))
    return observation
}

@Test("Both players with name, artist, duration and state give a GO for the source")
func sourceGo() {
    #expect(Verdict.source(music: player(), spotify: player()) == .go)
}

@Test("One player with all four is a reduced GO")
func sourceOnePlayer() {
    #expect(Verdict.source(music: player(), spotify: nil) == .reducedGo)
    #expect(Verdict.source(music: nil, spotify: player()) == .reducedGo)
    #expect(Verdict.source(music: player(), spotify: PlayerObservation()) == .reducedGo)
}

@Test("A player without a duration makes the source a reduced GO at best")
func sourceWithoutDuration() {
    #expect(Verdict.source(music: player(duration: false), spotify: player()) == .reducedGo)
    #expect(Verdict.source(music: player(duration: false), spotify: player(duration: false)) == .reducedGo)
}

@Test("No player, or none with a name and a state, is a NO-GO for the source")
func sourceNoGo() {
    #expect(Verdict.source(music: nil, spotify: nil) == .noGo)
    #expect(Verdict.source(music: player(name: false), spotify: player(state: false)) == .noGo)
    #expect(Verdict.source(music: PlayerObservation(), spotify: PlayerObservation()) == .noGo)
}

@Test("The flags of several events of a player are combined")
func observationCombinesEvents() {
    var observation = PlayerObservation()
    observation.record(PayloadInventory.Flags(hasName: true, hasState: true))
    observation.record(PayloadInventory.Flags(hasArtist: true, hasDuration: true))
    #expect(observation.events == 2)
    #expect(observation.flags.hasName && observation.flags.hasArtist && observation.flags.hasDuration && observation.flags.hasState)
}

@Test("Controls: both toggled is GO, one is reduced, none is NO-GO")
func controlsResults() {
    #expect(Verdict.controls(musicToggled: true, spotifyToggled: true) == .go)
    #expect(Verdict.controls(musicToggled: true, spotifyToggled: false) == .reducedGo)
    #expect(Verdict.controls(musicToggled: nil, spotifyToggled: true) == .reducedGo)
    #expect(Verdict.controls(musicToggled: false, spotifyToggled: false) == .noGo)
}

@Test("Controls that were not run are a NO-GO with the reason not run")
func controlsNotRun() {
    #expect(Verdict.controls(musicToggled: nil, spotifyToggled: nil) == .noGo)
    #expect(Verdict.controlsReason(musicToggled: nil, spotifyToggled: nil) == "not run")
    #expect(Verdict.controlsReason(musicToggled: false, spotifyToggled: nil) == "no key toggled playback")
}

private func perl(keys: Int, app: String?, label: String? = nil) -> RemoteObservation {
    RemoteObservation(route: "perl", keys: keys, app: app, label: label)
}

@Test("Remote: keys from an app that is neither Music nor Spotify give a GO")
func remoteGoByApp() {
    #expect(Verdict.remote([perl(keys: 7, app: "com.apple.Safari")]) == .go)
    #expect(Verdict.remote([perl(keys: 1, app: "com.google.Chrome", label: "browser")]) == .go)
}

@Test("Remote: keys with an unknown app and a browser, video or other label give a GO")
func remoteGoByLabel() {
    #expect(Verdict.remote([perl(keys: 4, app: nil, label: "browser")]) == .go)
    #expect(Verdict.remote([perl(keys: 4, app: nil, label: "video")]) == .go)
    #expect(Verdict.remote([perl(keys: 4, app: nil, label: "other")]) == .go)
}

@Test("Remote: keys only while Music or Spotify play, or an unknown app without a label, are a reduced GO")
func remoteReducedGo() {
    #expect(Verdict.remote([perl(keys: 7, app: "com.apple.Music", label: "music")]) == .reducedGo)
    #expect(Verdict.remote([perl(keys: 7, app: "com.spotify.client")]) == .reducedGo)
    #expect(Verdict.remote([perl(keys: 7, app: nil, label: "music")]) == .reducedGo)
    #expect(Verdict.remote([perl(keys: 7, app: nil)]) == .reducedGo)
    #expect(Verdict.remote([perl(keys: 7, app: "com.apple.Music", label: "browser")]) == .reducedGo)
}

@Test("Remote: one qualifying observation among several is enough for GO")
func remoteBestOfSeveral() {
    #expect(Verdict.remote([
        perl(keys: 0, app: nil, label: "browser"),
        perl(keys: 7, app: "com.apple.Music", label: "music"),
        perl(keys: 5, app: "com.apple.Safari", label: "browser"),
    ]) == .go)
}

@Test("Remote: nothing, no keys or a failed load are a NO-GO")
func remoteNoGo() {
    #expect(Verdict.remote([]) == .noGo)
    #expect(Verdict.remote([perl(keys: 0, app: "com.apple.Safari", label: "browser")]) == .noGo)
}

@Test("Remote: observations of the direct route never count")
func remoteDirectIgnored() {
    let direct = RemoteObservation(route: "direct", keys: 9, app: "com.apple.Safari", label: "browser")
    #expect(Verdict.remote([direct]) == .noGo)
    #expect(Verdict.remote([direct, perl(keys: 3, app: "com.apple.Music", label: "music")]) == .reducedGo)
}

@Test("A MEDIAREMOTE line parses to its route, key count and app")
func parseRemoteLine() {
    let line = "MEDIAREMOTE route=perl arch=arm64e loaded=y symbols=info:y;client:y;bundle:y;playing:y;notify:y result=keys:7 app=com.apple.Safari macos=27.2"
    let observation = RemoteObservation.parse(line: line, label: "browser")
    #expect(observation == RemoteObservation(route: "perl", keys: 7, app: "com.apple.Safari", label: "browser"))
}

@Test("Lines without keys, with a failed load or of another tag parse to zero keys or nil")
func parseOtherRemoteLines() {
    let empty = "MEDIAREMOTE route=perl arch=arm64 loaded=y symbols=info:y result=empty app=- macos=27.2"
    #expect(RemoteObservation.parse(line: empty)?.keys == 0)
    #expect(RemoteObservation.parse(line: empty)?.app == nil)
    let failed = "MEDIAREMOTE route=perl arch=x86_64 loaded=n symbols=- result=loadfail app=- macos=27.2"
    #expect(RemoteObservation.parse(line: failed)?.keys == 0)
    #expect(RemoteObservation.parse(line: "NOTIFY n=1 name=x") == nil)
    #expect(RemoteObservation.parse(line: "") == nil)
}

@Test("The summary line has the contract's keys in order, with a dash for what was not observed")
func summaryLineOrder() {
    var music = PlayerObservation()
    music.record(PayloadInventory.Flags(hasName: true, hasLocation: true, hasState: true))
    var spotify = PlayerObservation()
    spotify.record(PayloadInventory.Flags(hasName: true, hasPosition: true, hasState: true))
    let line = Verdict.summaryLine(
        music: music, spotify: spotify, others: 2, source: .reducedGo, controls: nil, remote: .noGo
    )
    #expect(line == "SUMMARY music=1 spotify=1 others=2 musicPosition=n spotifyPosition=y musicLocation=y source=REDUCED-GO controls=- remote=NO-GO")

    let nothing = Verdict.summaryLine(music: nil, spotify: nil, others: 0, source: nil, controls: nil, remote: nil)
    #expect(nothing == "SUMMARY music=0 spotify=0 others=0 musicPosition=- spotifyPosition=- musicLocation=- source=- controls=- remote=-")
}

@Test("A value with a space or a quote is quoted, an unknown value is a dash")
func reportLineQuoting() {
    #expect(ReportLine.format(tag: "X", [("a", "one two"), ("b", nil), ("c", ""), ("d", "q\"q"), ("e", "plain")])
        == "X a=\"one two\" b=- c=- d=\"q\\\"q\" e=plain")
}
