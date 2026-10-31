import Testing
@testable import HolzBarCore

@Suite("NowPlayingPlayers")
struct NowPlayingPlayersTests {
    @Test("A stored 1 is Music, 2 is Spotify and 3 is both; anything else reads as both")
    func storedValues() {
        #expect(NowPlayingPlayers(storedRawValue: 1) == .music)
        #expect(NowPlayingPlayers(storedRawValue: 2) == .spotify)
        #expect(NowPlayingPlayers(storedRawValue: 3) == .all)
        for bad in [0, 4, -1, 99, Int.max, Int.min] {
            #expect(NowPlayingPlayers(storedRawValue: bad) == .all)
        }
    }

    @Test("Containment follows the bits")
    func containment() {
        #expect(NowPlayingPlayers.music.contains(NowPlayingPlayer.music))
        #expect(!NowPlayingPlayers.music.contains(NowPlayingPlayer.spotify))
        #expect(NowPlayingPlayers.spotify.contains(NowPlayingPlayer.spotify))
        #expect(!NowPlayingPlayers.spotify.contains(NowPlayingPlayer.music))
        #expect(NowPlayingPlayers.all.contains(NowPlayingPlayer.music))
        #expect(NowPlayingPlayers.all.contains(NowPlayingPlayer.spotify))
        let other = NowPlayingPlayer(bundleIdentifier: "org.example.Player")
        #expect(!NowPlayingPlayers.all.contains(other))
    }

    @Test("Another player is allowed whatever the set holds, and Music and Spotify follow it")
    func allowance() {
        let other = NowPlayingPlayer(bundleIdentifier: "org.example.Player")
        for set in [NowPlayingPlayers.music, .spotify, .all] {
            #expect(set.allows(other))
        }
        #expect(NowPlayingPlayers.music.allows(NowPlayingPlayer.music))
        #expect(!NowPlayingPlayers.music.allows(NowPlayingPlayer.spotify))
        #expect(NowPlayingPlayers.spotify.allows(NowPlayingPlayer.spotify))
        #expect(!NowPlayingPlayers.spotify.allows(NowPlayingPlayer.music))
        #expect(NowPlayingPlayers.all.allows(NowPlayingPlayer.music) && NowPlayingPlayers.all.allows(NowPlayingPlayer.spotify))
    }

    @Test("The stored value of a set is its raw value")
    func storedRepresentation() {
        #expect(NowPlayingPlayers.music.rawValue == 1)
        #expect(NowPlayingPlayers.spotify.rawValue == 2)
        #expect(NowPlayingPlayers.all.rawValue == 3)
        #expect(NowPlayingPlayers(storedRawValue: NowPlayingPlayers.spotify.rawValue) == .spotify)
    }
}
