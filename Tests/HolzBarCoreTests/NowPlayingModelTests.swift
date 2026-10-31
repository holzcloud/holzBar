import Foundation
import Testing
@testable import HolzBarCore

@Suite("NowPlayingModel")
struct NowPlayingModelTests {
    private let other = NowPlayingPlayer(bundleIdentifier: "org.example.Player")

    private func event(
        _ player: NowPlayingPlayer,
        _ state: NowPlaybackState,
        title: String? = "Song"
    ) -> NowPlayingEvent {
        NowPlayingEvent(player: player, state: state, track: title.map { NowPlayingTrack(title: $0) })
    }

    @Test("A playing player beats a paused one, whichever is newer")
    func playingBeatsPaused() throws {
        var model = NowPlayingModel()
        model.handle(event(.music, .playing), at: 1)
        model.handle(event(.spotify, .paused), at: 2)
        #expect(try #require(model.current).player == .music)
    }

    @Test("Two playing players give the newer one")
    func newerPlayingWins() throws {
        var model = NowPlayingModel()
        model.handle(event(.music, .playing), at: 1)
        model.handle(event(.spotify, .playing), at: 2)
        #expect(try #require(model.current).player == .spotify)
        model.handle(event(.music, .playing), at: 3)
        #expect(try #require(model.current).player == .music)
    }

    @Test("If the current player stops, the other becomes current")
    func otherTakesOver() throws {
        var model = NowPlayingModel()
        model.handle(event(.music, .paused), at: 1)
        model.handle(event(.spotify, .playing), at: 2)
        model.handle(event(.spotify, .stopped, title: nil), at: 3)
        let current = try #require(model.current)
        #expect(current.player == .music)
        #expect(current.event.state == .paused)
    }

    @Test("A paused player beats a stopped one")
    func pausedBeatsStopped() throws {
        var model = NowPlayingModel()
        model.handle(event(.music, .paused), at: 1)
        model.handle(event(.spotify, .stopped, title: nil), at: 2)
        #expect(try #require(model.current).player == .music)
    }

    @Test("Clearing a player removes its state, and with nothing left there is no current state")
    func clearing() throws {
        var model = NowPlayingModel()
        model.handle(event(.music, .playing), at: 1)
        model.handle(event(.spotify, .paused), at: 2)
        model.clear(.music)
        #expect(try #require(model.current).player == .spotify)
        #expect(model.position(of: .music, at: 5) == nil)
        model.clear(.spotify)
        #expect(model.current == nil)
        #expect(model.isEmpty)
        model.handle(event(.music, .playing), at: 6)
        model.removeAll()
        #expect(model.current == nil)
    }

    @Test("A ninth player drops the one heard least recently")
    func ninthPlayerDrops() {
        var model = NowPlayingModel()
        let players = (0..<NowPlayingModel.maxPlayers + 1).map { NowPlayingPlayer(bundleIdentifier: "app.\($0)") }
        for (index, player) in players.enumerated() {
            model.handle(event(player, .paused), at: Double(index))
        }
        #expect(model.players.count == NowPlayingModel.maxPlayers)
        #expect(!model.players.contains(players[0]))
        #expect(model.players.contains(players[NowPlayingModel.maxPlayers]))
    }

    @Test("Hearing an old player again keeps it and drops a quieter one")
    func hearingKeepsAPlayer() {
        var model = NowPlayingModel()
        let players = (0..<NowPlayingModel.maxPlayers).map { NowPlayingPlayer(bundleIdentifier: "app.\($0)") }
        for (index, player) in players.enumerated() {
            model.handle(event(player, .paused), at: Double(index))
        }
        model.handle(event(players[0], .paused), at: 20)
        model.handle(event(other, .paused), at: 21)
        #expect(model.players.contains(players[0]))
        #expect(!model.players.contains(players[1]))
    }

    @Test("A player that is not Music or Spotify is handled like any other")
    func anyPlayer() throws {
        var model = NowPlayingModel()
        model.handle(event(other, .playing), at: 10)
        #expect(try #require(model.current).player == other)
        #expect(model.position(of: other, at: 14) == 4)
    }

    @Test("A state change without a song keeps the song that was loaded")
    func stateChangeKeepsTrack() throws {
        var model = NowPlayingModel()
        model.handle(event(.music, .playing, title: "Kept"), at: 1)
        model.handle(event(.music, .paused, title: nil), at: 2)
        let current = try #require(model.current)
        #expect(current.event.state == .paused)
        #expect(current.event.track?.title == "Kept")
        model.handle(event(.music, .stopped, title: nil), at: 3)
        #expect(try #require(model.current).event.track == nil)
    }
}
