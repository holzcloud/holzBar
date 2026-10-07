import Testing
@testable import HolzBarCore

@Suite("CaptureIndicator")
struct CaptureIndicatorTests {
    @Test("No badge while the setting is off")
    func noBadgeWhenOff() {
        #expect(CaptureIndicator.badge(isEnabled: false, isConcealing: true, isMicrophoneInUse: true, isCameraInUse: true) == nil)
        #expect(CaptureIndicator.badge(isEnabled: false, isConcealing: true, isMicrophoneInUse: true, isCameraInUse: false) == nil)
    }

    @Test("No badge while nothing is concealed")
    func noBadgeWhileNothingIsConcealed() {
        // Control Centre draws its own indicator then.
        #expect(CaptureIndicator.badge(isEnabled: true, isConcealing: false, isMicrophoneInUse: true, isCameraInUse: true) == nil)
        #expect(CaptureIndicator.badge(isEnabled: true, isConcealing: false, isMicrophoneInUse: false, isCameraInUse: true) == nil)
    }

    @Test("No badge while nothing records")
    func noBadgeWhileNothingRecords() {
        #expect(CaptureIndicator.badge(isEnabled: true, isConcealing: true, isMicrophoneInUse: false, isCameraInUse: false) == nil)
    }

    @Test("The badge says what is in use")
    func badgeSaysWhatIsInUse() {
        let microphone = CaptureIndicator.badge(isEnabled: true, isConcealing: true, isMicrophoneInUse: true, isCameraInUse: false)
        #expect(microphone == .microphone)
        #expect(microphone?.showsCamera == false)
        let camera = CaptureIndicator.badge(isEnabled: true, isConcealing: true, isMicrophoneInUse: false, isCameraInUse: true)
        #expect(camera == .camera)
        #expect(camera?.showsCamera == true)
        let both = CaptureIndicator.badge(isEnabled: true, isConcealing: true, isMicrophoneInUse: true, isCameraInUse: true)
        #expect(both == .cameraAndMicrophone)
        #expect(both?.showsCamera == true)
    }

    @Test("Suspended while concealing keeps the badge")
    func suspensionKeepsBadge() {
        // A bridged click on the clock releases every assertion for a moment.
        var suspension = SuspendedConcealment()
        suspension.begin(isConcealing: true)
        let isConcealing = false
        let during = CaptureIndicator.badge(
            isEnabled: true,
            isConcealing: suspension.conceals(isConcealing: isConcealing),
            isMicrophoneInUse: true,
            isCameraInUse: false
        )
        #expect(during == .microphone)
        // A second suspension begun meanwhile, while nothing is live, keeps what the first lifted.
        suspension.begin(isConcealing: isConcealing)
        #expect(suspension.conceals(isConcealing: false))
        suspension.end()
        #expect(!suspension.conceals(isConcealing: false))
        #expect(suspension.conceals(isConcealing: true))
    }

    @Test("A suspension while nothing is concealed adds no badge")
    func suspensionWithoutConcealmentAddsNoBadge() {
        var suspension = SuspendedConcealment()
        suspension.begin(isConcealing: false)
        let badge = CaptureIndicator.badge(
            isEnabled: true,
            isConcealing: suspension.conceals(isConcealing: false),
            isMicrophoneInUse: true,
            isCameraInUse: true
        )
        #expect(badge == nil)
    }

    @Test("The icon shows while it carries a badge")
    func iconShowsWithBadge() {
        #expect(CaptureIndicator.showsHolzBarIcon(isIconEnabled: true, badge: nil))
        #expect(CaptureIndicator.showsHolzBarIcon(isIconEnabled: true, badge: .microphone))
        #expect(CaptureIndicator.showsHolzBarIcon(isIconEnabled: false, badge: .camera))
        #expect(!CaptureIndicator.showsHolzBarIcon(isIconEnabled: false, badge: nil))
    }
}

@Suite("CaptureActivity")
struct CaptureActivityTests {
    let ownPID: Int32 = 500

    @Test("A new activity uses nothing")
    func newActivityUsesNothing() {
        let activity = CaptureActivity(ownPID: ownPID)
        #expect(!activity.isMicrophoneInUse)
        #expect(!activity.isCameraInUse)
    }

    @Test("A process that records uses the microphone until it stops")
    func recordingProcess() {
        var activity = CaptureActivity(ownPID: ownPID)
        activity.setInput(of: 7, pid: 42, isRunning: true)
        #expect(activity.isMicrophoneInUse)
        activity.setInput(of: 7, pid: 42, isRunning: false)
        #expect(!activity.isMicrophoneInUse)
    }

    @Test("holzBar's own process is never counted")
    func ownProcessIsIgnored() {
        var activity = CaptureActivity(ownPID: ownPID)
        activity.setInput(of: 9, pid: ownPID, isRunning: true)
        #expect(!activity.isMicrophoneInUse)
    }

    @Test("A process that quits while recording is forgotten")
    func quitWhileRecording() {
        var activity = CaptureActivity(ownPID: ownPID)
        activity.setInput(of: 7, pid: 42, isRunning: true)
        activity.setInput(of: 8, pid: 43, isRunning: true)
        activity.setInput(of: 7, pid: 42, isRunning: false)
        #expect(activity.isMicrophoneInUse)
        activity.keepProcesses([7])
        #expect(!activity.isMicrophoneInUse)
    }

    @Test("A camera unplugged while running is forgotten")
    func cameraUnplugged() {
        var activity = CaptureActivity(ownPID: ownPID)
        activity.setCamera(3, isRunning: true)
        #expect(activity.isCameraInUse)
        activity.keepCameras([])
        #expect(!activity.isCameraInUse)
    }

    @Test("Equal activities compare equal")
    func equalActivities() {
        var first = CaptureActivity(ownPID: ownPID)
        var second = CaptureActivity(ownPID: ownPID)
        first.setInput(of: 7, pid: 42, isRunning: true)
        second.setInput(of: 7, pid: 42, isRunning: true)
        #expect(first == second)
        second.setCamera(3, isRunning: true)
        #expect(first != second)
    }
}
