//
//  VerdictTests.swift
//  display-controls
//

import Testing
@testable import DisplayProbeCore

private func goodRead(
    changeTested: Bool = false,
    setSucceeded: Bool? = nil,
    readBack: Double? = nil,
    restored: Double? = nil
) -> Verdict.BrightnessObservation {
    Verdict.BrightnessObservation(
        loaded: true,
        symbolsResolved: 3,
        canChange: true,
        value: 0.62,
        changeTested: changeTested,
        setSucceeded: setSucceeded,
        readBack: readBack,
        target: 0.67,
        original: 0.62,
        restored: restored,
        slowestCallMs: 3
    )
}

@Test("Two levels agree within 0.02 and never when one is not a number")
func toleranceAgrees() {
    #expect(Tolerance.agrees(0.50, 0.51))
    #expect(!Tolerance.agrees(0.50, 0.53))
    #expect(!Tolerance.agrees(.nan, 0.5))
    #expect(!Tolerance.agrees(0.5, .infinity))
}

@Test("Brightness is NO-GO with the first failing reason")
func brightnessNoGo() {
    var notLoaded = goodRead()
    notLoaded.loaded = false
    #expect(Verdict.brightness(notLoaded).result == .noGo)
    #expect(Verdict.brightness(notLoaded).reason == "framework not loaded")

    var fewSymbols = goodRead()
    fewSymbols.symbolsResolved = 2
    #expect(Verdict.brightness(fewSymbols).result == .noGo)

    var cannotChange = goodRead()
    cannotChange.canChange = false
    #expect(Verdict.brightness(cannotChange).reason == "CanChange is false")

    var noValue = goodRead()
    noValue.value = nil
    #expect(Verdict.brightness(noValue).result == .noGo)

    var below = goodRead()
    below.value = -0.1
    var above = goodRead()
    above.value = 1.2
    #expect(Verdict.brightness(below).reason == "value outside 0 to 1")
    #expect(Verdict.brightness(above).reason == "value outside 0 to 1")

    var slow = goodRead()
    slow.slowestCallMs = 2100
    #expect(Verdict.brightness(slow).result == .noGo)
    #expect(Verdict.brightness(slow).reason == "a call took longer than 2 seconds")
}

@Test("A good read without a change test is REDUCED-GO and read only")
func brightnessReadOnly() {
    let verdict = Verdict.brightness(goodRead())
    #expect(verdict.result == .reducedGo)
    #expect(verdict.reason == "read only")
}

@Test("A change that read back and was restored within 0.02 is GO")
func brightnessGo() {
    let verdict = Verdict.brightness(goodRead(changeTested: true, setSucceeded: true, readBack: 0.668, restored: 0.621))
    #expect(verdict.result == .go)
}

@Test("A set that failed, did not read back or was not restored is REDUCED-GO")
func brightnessChangeFails() {
    let failed = Verdict.brightness(goodRead(changeTested: true, setSucceeded: false))
    #expect(failed.result == .reducedGo)
    #expect(failed.reason == "set failed")

    let notRead = Verdict.brightness(goodRead(changeTested: true, setSucceeded: true, readBack: 0.62, restored: 0.62))
    #expect(notRead.result == .reducedGo)
    #expect(notRead.reason == "set did not read back")

    let notRestored = Verdict.brightness(goodRead(changeTested: true, setSucceeded: true, readBack: 0.67, restored: 0.67))
    #expect(notRestored.result == .reducedGo)
    #expect(notRestored.reason == "original not restored")
}

@Test("The external displays are listed by number and none is a dash")
func externalList() {
    #expect(Verdict.externalList([]) == nil)
    #expect(Verdict.externalList([3, 7]) == "3,7")
}

private func goodVolume(
    plan: Verdict.VolumePlan = .virtualMain,
    transport: Verdict.Transport = .builtIn,
    changeTested: Bool = true,
    readBack: Double? = 0.55,
    restored: Double? = 0.50,
    muteSettable: Bool = true,
    listener: Verdict.ListenerState = .fired
) -> Verdict.VolumeObservation {
    Verdict.VolumeObservation(
        plan: plan,
        transport: transport,
        changeTested: changeTested,
        original: 0.50,
        target: 0.55,
        readBack: readBack,
        restored: restored,
        muteSettable: muteSettable,
        listener: listener
    )
}

@Test("The change target is plus 0.05, minus 0.05 above 0.95 and never below 0.05")
func changeTarget() {
    #expect(Tolerance.agrees(Verdict.target(from: 0.50), 0.55, within: 0.0001))
    #expect(Tolerance.agrees(Verdict.target(from: 0.97), 0.92, within: 0.0001))
    #expect(Tolerance.agrees(Verdict.target(from: 0.95), 1.0, within: 0.0001))
    #expect(Tolerance.agrees(Verdict.target(from: 0.0), 0.05, within: 0.0001))
    #expect(Tolerance.agrees(Verdict.target(from: .nan), 0.5, within: 0.0001))
}

@Test("The plan is a word chosen from what is settable, the virtual main volume first")
func planWord() {
    #expect(Verdict.VolumePlan.choose(virtualMainSettable: true, mainScalarSettable: true, settableChannels: 2) == .virtualMain)
    #expect(Verdict.VolumePlan.choose(virtualMainSettable: false, mainScalarSettable: true, settableChannels: 2) == .mainScalar)
    #expect(Verdict.VolumePlan.choose(virtualMainSettable: false, mainScalarSettable: false, settableChannels: 2) == .channels)
    #expect(Verdict.VolumePlan.choose(virtualMainSettable: false, mainScalarSettable: false, settableChannels: 0) == .none)
    #expect(Verdict.VolumePlan.virtualMain.rawValue == "virtualMain")
}

@Test("Volume is NO-GO when the output has no settable volume")
func volumeNoGo() {
    let verdict = Verdict.volume(goodVolume(plan: .none))
    #expect(verdict.result == .noGo)
    #expect(verdict.reason == "no settable volume")
}

@Test("An output without a volume on a display transport is not judged NO-GO")
func volumeDisplayTransport() {
    #expect(Verdict.volume(goodVolume(plan: .none, transport: .hdmi)).result == .reducedGo)
    #expect(Verdict.volume(goodVolume(plan: .none, transport: .displayPort)).result == .reducedGo)
}

@Test("A settable volume without a change test is REDUCED-GO")
func volumeNotTested() {
    let verdict = Verdict.volume(goodVolume(changeTested: false, readBack: nil, restored: nil))
    #expect(verdict.result == .reducedGo)
    #expect(verdict.reason == "change not tested")
}

@Test("A volume that read back and restored with a mute and a listener is GO")
func volumeGo() {
    #expect(Verdict.volume(goodVolume()).result == .go)
}

@Test("A missing mute or a silent listener is REDUCED-GO and named")
func volumeMuteOrListener() {
    let noMute = Verdict.volume(goodVolume(muteSettable: false))
    #expect(noMute.result == .reducedGo)
    #expect(noMute.reason == "no settable mute")

    let silent = Verdict.volume(goodVolume(listener: .silent))
    #expect(silent.result == .reducedGo)
    #expect(silent.reason == "listener silent")

    let both = Verdict.volume(goodVolume(muteSettable: false, listener: .silent))
    #expect(both.reason == "no settable mute, listener silent")
}

@Test("A change that did not read back or was not restored is REDUCED-GO")
func volumeChangeFails() {
    #expect(Verdict.volume(goodVolume(readBack: 0.50)).reason == "change did not read back")
    #expect(Verdict.volume(goodVolume(restored: 0.55)).reason == "original not restored")
}

@Test("The listener words are fired, silent and not run")
func listenerWords() {
    #expect(Verdict.ListenerState.fired.rawValue == "fired")
    #expect(Verdict.ListenerState.silent.rawValue == "silent")
    #expect(Verdict.ListenerState.notRun.rawValue == "not run")
}
