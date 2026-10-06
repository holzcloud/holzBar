import Testing
@testable import HolzBarCore

@Suite("SettingsSyncPause")
struct SettingsSyncPauseTests {
    @Test("Sync is paused in 0.0.7-beta2")
    func pausedInThisBuild() {
        #expect(SettingsSyncPause.isPaused)
        #expect(!SettingsSyncPause.syncs(isTurnedOn: true))
        #expect(!SettingsSyncPause.allowsChanges())
    }

    @Test("While paused, sync never runs, even when it is turned on")
    func pausedNeverSyncs() {
        #expect(!SettingsSyncPause.syncs(isTurnedOn: true, isPaused: true))
        #expect(!SettingsSyncPause.syncs(isTurnedOn: false, isPaused: true))
        #expect(!SettingsSyncPause.allowsChanges(isPaused: true))
    }

    @Test("Without the pause, sync runs only when it is turned on")
    func unpausedFollowsTheChoice() {
        #expect(SettingsSyncPause.syncs(isTurnedOn: true, isPaused: false))
        #expect(!SettingsSyncPause.syncs(isTurnedOn: false, isPaused: false))
        #expect(SettingsSyncPause.allowsChanges(isPaused: false))
    }
}
