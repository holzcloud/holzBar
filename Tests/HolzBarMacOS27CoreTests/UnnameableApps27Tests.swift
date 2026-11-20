import Testing
@testable import HolzBarMacOS27Core

@Suite("UnnameableApps27")
struct UnnameableApps27Tests {
    func isUnnameable(_ path: String?, bundleID: String? = "com.example.app") -> Bool {
        UnnameableApps27.isUnnameable(bundleID: bundleID, bundlePath: path)
    }

    @Test("Apps run from /Applications or /System are named", arguments: [
        "/Applications/Safari.app",
        "/applications/Lower.app",
        "/Applications/Utilities/Tool.app",
        "/Applications/Host.app/Contents/Library/LoginItems/Helper.app",
        "/System/Applications/Mail.app",
        "/System/Library/CoreServices/TextInputMenuAgent.app",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
    ])
    func named(path: String) {
        #expect(!isUnnameable(path))
    }

    @Test("Apps run from anywhere else cannot be named (macOS 27.2)", arguments: [
        "/opt/vendor/bin/Agent.app",
        "/Users/someone/Applications/holzBar.app",
        "/Applications.old/App.app",
        "/Library/Application Support/Vendor/Agent.app",
        "/Applications/../opt/vendor/Agent.app",
    ])
    func unnameable(path: String) {
        #expect(isUnnameable(path))
    }

    @Test("Without a bundle path the rule cannot name the app")
    func noPath() {
        #expect(isUnnameable(nil))
    }

    @Test("Without a bundle identifier the pure rule answers unnameable")
    func noBundleID() {
        #expect(isUnnameable("/Applications/Safari.app", bundleID: nil))
        #expect(isUnnameable("/opt/vendor/bin/Agent.app", bundleID: nil))
    }

    typealias Owner = UnnameableApps27.Owner

    @Test("Owners keep first-seen order and drop duplicates")
    func ownersOrder() {
        let owners = [
            Owner(bundleID: "b", bundlePath: "/opt/b.app"),
            Owner(bundleID: "a", bundlePath: "/opt/a.app"),
            Owner(bundleID: "b", bundlePath: "/opt/b.app"),
        ]
        #expect(UnnameableApps27.owners(owners, confirmed: []) == ["b", "a"])
    }

    @Test("A named owner counts only when HiddenAnyway27 confirmed it")
    func ownersConfirmed() {
        let owners = [
            Owner(bundleID: "named", bundlePath: "/Applications/Named.app"),
            Owner(bundleID: "confirmed", bundlePath: "/Applications/Confirmed.app"),
            Owner(bundleID: "nopath", bundlePath: nil),
        ]
        #expect(UnnameableApps27.owners(owners, confirmed: ["confirmed"]) == ["confirmed", "nopath"])
    }

    @Test("No owners, no unnameable apps")
    func ownersEmpty() {
        #expect(UnnameableApps27.owners([], confirmed: ["x"]).isEmpty)
    }
}
