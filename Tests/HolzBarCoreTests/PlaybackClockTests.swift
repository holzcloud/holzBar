import Foundation
import Testing
@testable import HolzBarCore

@Suite("PlaybackClock")
struct PlaybackClockTests {
    private let song = NowPlayingTrack(title: "A", artist: "B", duration: 200, id: "one")
    private let other = NowPlayingTrack(title: "C", artist: "D", duration: 100, id: "two")

    private func event(
        _ state: NowPlaybackState,
        track: NowPlayingTrack? = nil,
        position: Double? = nil
    ) -> NowPlayingEvent {
        NowPlayingEvent(player: .music, state: state, track: track, position: position)
    }

    @Test("Playing from the start counts the seconds since")
    func playingCounts() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        #expect(clock.position(at: 100) == 0)
        #expect(clock.position(at: 105) == 5)
    }

    @Test("Pausing holds the position and resuming goes on from it")
    func pauseAndResume() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        clock.apply(event(.paused), at: 110)
        #expect(clock.position(at: 110) == 10)
        #expect(clock.position(at: 200) == 10)
        clock.apply(event(.playing), at: 200)
        #expect(clock.position(at: 205) == 15)
    }

    @Test("A reported position replaces the count and counting goes on from it")
    func reportedPositionReplaces() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        clock.apply(event(.playing, track: song, position: 50), at: 110)
        #expect(clock.position(at: 110) == 50)
        #expect(clock.position(at: 114) == 54)
        clock.apply(event(.paused, track: song, position: 60), at: 120)
        #expect(clock.position(at: 300) == 60)
    }

    @Test("A repeated playing event for the same song does not reset the count")
    func sameSongDoesNotReset() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        clock.apply(event(.playing, track: song), at: 130)
        #expect(clock.position(at: 140) == 40)
    }

    @Test("A new song resets the count to its reported position, or to 0")
    func newTrackResets() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        clock.apply(event(.playing, track: other), at: 130)
        #expect(clock.position(at: 130) == 0)
        #expect(clock.position(at: 132) == 2)
        clock.apply(event(.playing, track: song, position: 7), at: 140)
        #expect(clock.position(at: 140) == 7)
        #expect(clock.position(at: 141) == 8)
    }

    @Test("Stopping resets the count, and the same song then starts from 0")
    func stoppedResets() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        clock.apply(event(.stopped), at: 150)
        #expect(clock.position(at: 160) == 0)
        clock.apply(event(.playing, track: song), at: 170)
        #expect(clock.position(at: 175) == 5)
    }

    @Test("The position never exceeds the length of the song or goes below 0")
    func positionIsClamped() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: song), at: 100)
        #expect(clock.position(at: 10_000) == 200)
        #expect(clock.position(at: 50) == 0)
        clock.apply(event(.playing, track: song, position: 9_999), at: 200)
        #expect(clock.position(at: 200) == 200)
    }

    @Test("A song without a length is not clamped above")
    func unknownDuration() {
        var clock = PlaybackClock()
        clock.apply(event(.playing, track: NowPlayingTrack(title: "No length")), at: 0)
        #expect(clock.position(at: 5_000) == 5_000)
    }

    @Test("Without any event there is no position, and a bad reported position is ignored")
    func noStateAndBadPosition() {
        var clock = PlaybackClock()
        #expect(clock.position(at: 10) == nil)
        clock.apply(event(.playing, track: song), at: 0)
        clock.apply(event(.playing, track: song, position: -3), at: 10)
        #expect(clock.position(at: 10) == 10)
        clock.apply(event(.playing, track: song, position: .nan), at: 20)
        #expect(clock.position(at: 20) == 20)
    }
}
