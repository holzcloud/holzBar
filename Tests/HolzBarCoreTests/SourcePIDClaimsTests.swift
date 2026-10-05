import Foundation
import Testing
@testable import HolzBarCore

/// On macOS 26 apps report their item frames themselves, so another app could claim
/// Control Center's camera and microphone indicator, or another app's item.
@Suite("SourcePIDClaims")
struct SourcePIDClaimsTests {
    // The claims are changed outside `#expect`, whose expansion cannot call a mutating method.

    private let controlCenter = SourcePIDClaims.Claim(pid: 10, isSignedByApple: true)
    private let screenCaptureUI = SourcePIDClaims.Claim(pid: 11, isSignedByApple: true)
    private let loginItem = SourcePIDClaims.Claim(pid: 20, isSignedByApple: false)
    private let otherApp = SourcePIDClaims.Claim(pid: 21, isSignedByApple: false)

    private func claims(_ list: [SourcePIDClaims.Claim]) -> SourcePIDClaims {
        var claims = SourcePIDClaims()
        for claim in list {
            claims.add(claim)
        }
        return claims
    }

    @Test("A window nobody claims has no app")
    func unclaimed() {
        let empty = SourcePIDClaims()
        #expect(empty.decision(scanFinished: true, appleAppsComplete: true) == .unresolved)
        #expect(empty.decision(scanFinished: false, appleAppsComplete: true) == .unresolved)
        #expect(!empty.isSettled)
    }

    @Test("An app signed by Apple gets the window, even from a scan that stopped early")
    func appleClaimWins() {
        let claimed = claims([controlCenter])
        #expect(claimed.isSettled)
        #expect(claimed.decision(scanFinished: true, appleAppsComplete: true) == .owner(10))
        #expect(claimed.decision(scanFinished: false, appleAppsComplete: true) == .owner(10))
    }

    @Test("Control Center keeps its indicator when another app claims it too, in either order")
    func appleClaimBeatsOtherApp() {
        #expect(claims([controlCenter, loginItem]).decision(scanFinished: true, appleAppsComplete: true) == .owner(10))
        #expect(claims([loginItem, controlCenter]).decision(scanFinished: true, appleAppsComplete: true) == .owner(10))
        #expect(claims([loginItem, otherApp, controlCenter]).decision(scanFinished: true, appleAppsComplete: true) == .owner(10))
    }

    @Test("The first app signed by Apple wins")
    func firstAppleClaimWins() {
        #expect(claims([screenCaptureUI, controlCenter]).decision(scanFinished: true, appleAppsComplete: true) == .owner(11))
    }

    @Test("Another app gets the window only after a finished scan")
    func otherAppNeedsFinishedScan() {
        let claimed = claims([loginItem])
        #expect(!claimed.isSettled)
        #expect(claimed.decision(scanFinished: true, appleAppsComplete: true) == .owner(20))
        #expect(claimed.decision(scanFinished: false, appleAppsComplete: true) == .unresolved)
    }

    @Test("Two items of one app at the same centre are one claim")
    func sameAppTwice() {
        #expect(claims([loginItem, loginItem]).decision(scanFinished: true, appleAppsComplete: true) == .owner(20))
    }

    @Test("Another app gets no window while an app signed by Apple was skipped")
    func otherAppWaitsForAppleApps() {
        // Control Center was paused or timed out, so its indicator could be at this centre.
        let claimed = claims([loginItem])
        #expect(claimed.decision(scanFinished: true, appleAppsComplete: false) == .unresolved)
        #expect(claimed.decision(scanFinished: false, appleAppsComplete: false) == .unresolved)
    }

    @Test("An app signed by Apple gets the window while another one was skipped")
    func appleClaimWinsWhileAppleAppSkipped() {
        #expect(claims([controlCenter]).decision(scanFinished: true, appleAppsComplete: false) == .owner(10))
        #expect(claims([loginItem, controlCenter]).decision(scanFinished: false, appleAppsComplete: false) == .owner(10))
    }

    @Test("A window two other apps claim belongs to neither")
    func contested() {
        let claimed = claims([loginItem, otherApp])
        #expect(!claimed.isSettled)
        #expect(claimed.decision(scanFinished: true, appleAppsComplete: true) == .contested)
        #expect(claimed.decision(scanFinished: false, appleAppsComplete: true) == .contested)
        #expect(claimed.decision(scanFinished: true, appleAppsComplete: false) == .contested)
    }
}
