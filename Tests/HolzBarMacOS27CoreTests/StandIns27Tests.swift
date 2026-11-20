import Testing
@testable import HolzBarMacOS27Core

@Suite("StandIns27")
struct StandIns27Tests {
    func plan(
        isEnabled: Bool = true,
        holzBarIsNameable: Bool = true,
        _ unnameableVisible: [String] = ["com.example.agent"],
        isConcealing: Bool = true,
        isHoldingRelease: Bool = false
    ) -> StandIns27.Plan {
        StandIns27.plan(
            isEnabled: isEnabled,
            holzBarIsNameable: holzBarIsNameable,
            unnameableVisible: unnameableVisible,
            isConcealing: isConcealing,
            isHoldingRelease: isHoldingRelease
        )
    }

    @Test("Nothing is drawn with the switch off")
    func switchOff() {
        #expect(plan(isEnabled: false) == StandIns27.none)
    }

    @Test("Nothing is drawn when holzBar itself runs from a place MenuBarAgent cannot name")
    func holzBarUnnamed() {
        #expect(plan(holzBarIsNameable: false) == StandIns27.none)
    }

    @Test("Nothing is drawn while nothing is concealed and no hold lasts")
    func nothingConcealed() {
        #expect(plan(isConcealing: false) == StandIns27.none)
    }

    @Test("While concealing, every app gets one stand-in, in bar order")
    func concealing() {
        let result = plan(["com.example.b", "com.example.a", "com.example.b"])
        #expect(result.bundleIDs == ["com.example.b", "com.example.a"])
        #expect(result.isShown)
    }

    @Test("While a hold lasts the stand-ins keep their places but are not drawn")
    func holding() {
        let result = plan(isConcealing: false, isHoldingRelease: true)
        #expect(result.bundleIDs == ["com.example.agent"])
        #expect(!result.isShown)
    }

    @Test("No unnameable app means no stand-in")
    func empty() {
        let result = plan([])
        #expect(result.bundleIDs.isEmpty)
    }

    @Test("The autosave name is the FNV-1a hash of the bundle identifier", arguments: [
        ("", "cbf29ce484222325"),
        ("a", "af63dc4c8601ec8c"),
    ])
    func hashVectors(bundleID: String, digits: String) {
        #expect(StandIns27.autosaveName(for: bundleID) == "holzBar.StandIn." + digits)
    }

    @Test("The autosave name is stable, distinct, hides the identifier and avoids the widget prefix")
    func autosaveName() {
        let first = StandIns27.autosaveName(for: "com.example.agent")
        #expect(first == StandIns27.autosaveName(for: "com.example.agent"))
        #expect(first != StandIns27.autosaveName(for: "com.example.other"))
        #expect(first.hasPrefix(StandIns27.autosaveNamePrefix))
        #expect(!first.hasPrefix("holzBar.Widget."))
        #expect(!first.contains("example"))
        let digits = first.dropFirst(StandIns27.autosaveNamePrefix.count)
        #expect(digits.count == 16)
        #expect(digits.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("Every name has exactly 16 hex digits, also when the hash starts with zeros")
    func padded() {
        for index in 0..<2000 {
            let name = StandIns27.autosaveName(for: "pad.\(index)")
            #expect(name.count == StandIns27.autosaveNamePrefix.count + 16)
        }
    }
}
