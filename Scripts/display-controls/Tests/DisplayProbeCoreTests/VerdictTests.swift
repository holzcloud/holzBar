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
