import Foundation
import Testing

@Suite("SimGroundTruth")
struct SimGroundTruthTests {
    /// A hand-built trace over three Macs. The snapshot the tests set stands in for the world's holders.
    private func tracker() -> (SimGroundTruth, Box) {
        let truth = SimGroundTruth()
        let box = Box()
        truth.holderSource = { box.snapshot }
        return (truth, box)
    }

    final class Box {
        var snapshot = SimHolderSnapshot()
    }

    @Test("Past follows program order and ingest edges, and reading without deciding is no ingest")
    func pastFollowsIngestEdges() {
        let (truth, _) = tracker()
        let c1 = truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        truth.recordWrite(version: 1, writer: .A, path: "holzBar/Macs/A.plist", time: 2)
        let c2 = truth.recordUserChange(mac: .B, unit: "UseIceBar", tokens: ["u2@UseIceBar"], time: 3)
        // B reads A's file but has not decided: nothing joins yet.
        truth.recordWrite(version: 2, writer: .B, path: "holzBar/Macs/B.plist", time: 4)
        #expect(truth.past(ofVersion: 1) == [c1])
        #expect(truth.past(ofVersion: 2) == [c2])
        truth.recordIngest(mac: .B, version: 1, time: 5)
        truth.recordWrite(version: 3, writer: .B, path: "holzBar/Macs/B.plist", time: 6)
        #expect(truth.past(ofVersion: 3) == [c1, c2])
        #expect(truth.past(ofMac: .B) == [c1, c2])
        #expect(truth.past(ofMac: .A) == [c1])
        #expect(truth.past(ofMac: .C).isEmpty)
        // Ingest edges are transitive: C ingests B's version and so learns of A's change.
        truth.recordIngest(mac: .C, version: 3, time: 7)
        #expect(truth.past(ofMac: .C) == [c1, c2])
    }

    @Test("A change stays live until a later informed user change on the same unit")
    func livenessAndInformedSupersession() {
        let (truth, _) = tracker()
        truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        truth.recordWrite(version: 1, writer: .A, path: "p", time: 2)
        // B edits the same unit without having seen A's change: both stay live.
        truth.recordUserChange(mac: .B, unit: "ShowOnHover", tokens: ["u2@ShowOnHover"], time: 3)
        #expect(truth.isLive(token: "u1@ShowOnHover", unit: "ShowOnHover"))
        #expect(truth.isLive(token: "u2@ShowOnHover", unit: "ShowOnHover"))
        // B edits another unit: nothing is superseded.
        truth.recordUserChange(mac: .B, unit: "UseIceBar", tokens: ["u3@UseIceBar"], time: 4)
        #expect(truth.isLive(token: "u2@ShowOnHover", unit: "ShowOnHover"))
        // B informs itself and edits again: its own earlier change and A's are superseded.
        truth.recordIngest(mac: .B, version: 1, time: 5)
        truth.recordUserChange(mac: .B, unit: "ShowOnHover", tokens: ["u4@ShowOnHover"], time: 6)
        #expect(!truth.isLive(token: "u1@ShowOnHover", unit: "ShowOnHover"))
        #expect(!truth.isLive(token: "u2@ShowOnHover", unit: "ShowOnHover"))
        #expect(truth.isLive(token: "u4@ShowOnHover", unit: "ShowOnHover"))
        #expect(truth.isLive(token: "u3@UseIceBar", unit: "UseIceBar"))
        #expect(!truth.isLive(token: "u4@ShowOnHover", unit: "UseIceBar"))
        // A user delete is a user change on the unit.
        truth.recordUserChange(mac: .B, unit: "ShowOnHover", tokens: [], time: 7)
        #expect(!truth.isLive(token: "u4@ShowOnHover", unit: "ShowOnHover"))
    }

    @Test("An answer supersedes exactly the values its prompt showed as the losing alternative")
    func answersSupersedeShownLosers() {
        func scenario(_ answer: SimAnswer) -> (local: Bool, folder: Bool, other: Bool) {
            let (truth, _) = tracker()
            truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
            truth.recordUserChange(mac: .B, unit: "ShowOnHover", tokens: ["u2@ShowOnHover"], time: 2)
            truth.recordUserChange(mac: .B, unit: "UseIceBar", tokens: ["u3@UseIceBar"], time: 2)
            let prompt = SimPrompt(id: 1, title: "Sync", shown: [
                SimPromptUnit(unit: "ShowOnHover", local: "u2@ShowOnHover", folder: "u1@ShowOnHover"),
            ])
            truth.recordPrompt(mac: .B, prompt: prompt, time: 3)
            truth.recordAnswer(mac: .B, prompt: prompt, answer: answer, time: 4)
            return (
                truth.isLive(token: "u2@ShowOnHover", unit: "ShowOnHover"),
                truth.isLive(token: "u1@ShowOnHover", unit: "ShowOnHover"),
                truth.isLive(token: "u3@UseIceBar", unit: "UseIceBar")
            )
        }
        #expect(scenario(.use) == (false, true, true))
        #expect(scenario(.keep) == (true, false, true))
        #expect(scenario(.later) == (true, true, true))
        #expect(scenario(.cancel) == (true, true, true))
        #expect(scenario(.pick(["ShowOnHover": .folder])) == (false, true, true))
        #expect(scenario(.pick(["ShowOnHover": .local])) == (true, false, true))
        #expect(scenario(.pick(["UseIceBar": .local])) == (true, true, true))
    }

    @Test("A live change is globally lost when no defaults, readable file or pending holding carries its token")
    func globalLoss() {
        let (truth, box) = tracker()
        truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        box.snapshot = SimHolderSnapshot(defaults: [.A: ["u1@ShowOnHover"]])
        truth.observe(cause: .nonSync, time: 1)
        #expect(truth.globallyLost().isEmpty)

        // A file in a replica carries it.
        box.snapshot = SimHolderSnapshot(
            defaults: [.A: []],
            files: [SimHeldFile(place: "F1:B:p", mac: .B, path: "p", version: 1, tokens: ["u1@ShowOnHover"])]
        )
        truth.observe(cause: .sync, time: 2)
        #expect(truth.globallyLost().isEmpty)

        // A pending holding carries it.
        box.snapshot = SimHolderSnapshot(pending: [.C: ["u1@ShowOnHover"]])
        truth.observe(cause: .sync, time: 3)
        #expect(truth.globallyLost().isEmpty)

        // Nothing carries it any more.
        box.snapshot = SimHolderSnapshot()
        truth.observe(cause: .sync, time: 4)
        #expect(truth.globallyLost() == ["u1@ShowOnHover"])
        #expect(truth.globallyLost(at: 0).isEmpty)

        // A superseded change is not a loss.
        truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u2@ShowOnHover"], time: 5)
        box.snapshot = SimHolderSnapshot(defaults: [.A: ["u2@ShowOnHover"]])
        truth.observe(cause: .nonSync, time: 5)
        #expect(truth.globallyLost().isEmpty)
    }

    @Test("A loss where every holder was destroyed by non-sync events is excluded")
    func nonSyncDestructionIsExcluded() {
        func lost(removals: [SimStepCause]) -> [String] {
            let (truth, box) = tracker()
            truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
            box.snapshot = SimHolderSnapshot(
                defaults: [.A: ["u1@ShowOnHover"]],
                files: [SimHeldFile(place: "F1:B:p", mac: .B, path: "p", version: 1, tokens: ["u1@ShowOnHover"])]
            )
            truth.observe(cause: .sync, time: 2)
            // The file holder goes first, then the defaults holder.
            box.snapshot = SimHolderSnapshot(defaults: [.A: ["u1@ShowOnHover"]])
            truth.observe(cause: removals[0], time: 3)
            box.snapshot = SimHolderSnapshot()
            truth.observe(cause: removals[1], time: 4)
            return truth.globallyLost()
        }
        #expect(lost(removals: [.nonSync, .nonSync]).isEmpty)
        #expect(lost(removals: [.sync, .nonSync]) == ["u1@ShowOnHover"])
        #expect(lost(removals: [.nonSync, .sync]) == ["u1@ShowOnHover"])
        #expect(lost(removals: [.sync, .sync]) == ["u1@ShowOnHover"])
    }

    @Test("Conflict is per unit: both sides need a live change on the unit that the other lacks, with different values")
    func perUnitConflict() {
        let (truth, box) = tracker()
        truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        truth.recordUserChange(mac: .B, unit: "ShowOnHover", tokens: ["u2@ShowOnHover"], time: 2)
        truth.recordUserChange(mac: .B, unit: "UseIceBar", tokens: ["u3@UseIceBar"], time: 2)
        truth.recordWrite(version: 7, writer: .B, path: "holzBar/Macs/B.plist", time: 3)
        box.snapshot = SimHolderSnapshot(
            defaults: [.A: ["u1@ShowOnHover"], .B: ["u2@ShowOnHover", "u3@UseIceBar"]],
            files: [SimHeldFile(
                place: "F1:A:b", mac: .A, path: "holzBar/Macs/B.plist", version: 7,
                tokens: ["u2@ShowOnHover", "u3@UseIceBar"]
            )]
        )
        // The same unit changed to different values concurrently conflicts.
        #expect(truth.conflict(mac: .A, unit: "ShowOnHover"))
        #expect(truth.conflictingVersions(mac: .A, unit: "ShowOnHover") == [7])
        // A unit only B changed does not: A has nothing live there.
        #expect(!truth.conflict(mac: .A, unit: "UseIceBar"))
        // Different units changed on two Macs merge without a question.
        let (other, otherBox) = tracker()
        other.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        other.recordUserChange(mac: .B, unit: "UseIceBar", tokens: ["u2@UseIceBar"], time: 2)
        other.recordWrite(version: 8, writer: .B, path: "b", time: 3)
        otherBox.snapshot = SimHolderSnapshot(
            defaults: [.A: ["u1@ShowOnHover"]],
            files: [SimHeldFile(place: "F1:A:b", mac: .A, path: "b", version: 8, tokens: ["u2@UseIceBar"])]
        )
        #expect(!other.conflict(mac: .A, unit: "ShowOnHover"))
        #expect(!other.conflict(mac: .A, unit: "UseIceBar"))
        // Once A ingests B's version it is informed, and no conflict remains.
        truth.recordIngest(mac: .A, version: 7, time: 9)
        #expect(!truth.conflict(mac: .A, unit: "ShowOnHover"))
    }

    @Test("Origins are user, automatic, pre or unknown")
    func origins() {
        let (truth, _) = tracker()
        truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        truth.recordAutomaticChange(mac: .A, unit: "known27", tokens: ["auto-A-2"], time: 2)
        #expect(truth.origin(of: "u1@ShowOnHover") == .user)
        #expect(truth.origin(of: "auto-A-2") == .automatic)
        #expect(truth.origin(of: "auto-B-9") == .automatic)
        #expect(truth.origin(of: "pre(B)") == .pre)
        #expect(truth.origin(of: "default") == .unknown)
        // An automatic change is no part of any past.
        truth.recordWrite(version: 1, writer: .A, path: "p", time: 3)
        #expect(truth.past(ofVersion: 1).count == 1)
    }

    @Test("Units of the macOS 27 families are comparable only on generation 27 Macs")
    func generationScope() {
        func conflict(generation: Int, unit: String) -> Bool {
            let (truth, box) = tracker()
            truth.setGeneration(generation, of: .A)
            truth.recordUserChange(mac: .A, unit: unit, tokens: ["u1@\(unit)"], time: 1)
            truth.recordUserChange(mac: .B, unit: unit, tokens: ["u2@\(unit)"], time: 2)
            truth.recordWrite(version: 1, writer: .B, path: "b", time: 3)
            box.snapshot = SimHolderSnapshot(
                defaults: [.A: ["u1@\(unit)"]],
                files: [SimHeldFile(place: "F1:A:b", mac: .A, path: "b", version: 1, tokens: ["u2@\(unit)"])]
            )
            return truth.conflict(mac: .A, unit: unit)
        }
        #expect(conflict(generation: 27, unit: "l27/com.app.a"))
        #expect(!conflict(generation: 26, unit: "l27/com.app.a"))
        #expect(conflict(generation: 27, unit: "prof/work"))
        #expect(!conflict(generation: 26, unit: "prof/work"))
        #expect(conflict(generation: 27, unit: "known27"))
        #expect(!conflict(generation: 26, unit: "known27"))
        #expect(conflict(generation: 26, unit: "ShowOnHover"))
        #expect(SimUnits.generationScope("l27/x") == 27)
        #expect(SimUnits.generationScope("ItemSections/x") == nil)
    }

    @Test("A provider conflict copy has the past of the content it holds")
    func copiesShareThePast() {
        let (truth, _) = tracker()
        let c1 = truth.recordUserChange(mac: .A, unit: "ShowOnHover", tokens: ["u1@ShowOnHover"], time: 1)
        truth.recordWrite(version: 1, writer: .A, path: "holzBar/Settings.plist", time: 2)
        truth.recordCopy(version: 2, of: 1, path: "holzBar/Settings-MARKER-NAME-A.plist", time: 3)
        truth.recordForeign(version: 3, path: "holzBar/Settings.plist", time: 4)
        #expect(truth.past(ofVersion: 2) == [c1])
        #expect(truth.past(ofVersion: 3).isEmpty)
    }

    // MARK: Hooked into the world

    @Test("The world records writes, ingests, prompts and answers, and shows a beta1 global loss")
    func worldRecordsAndFindsBeta1Loss() throws {
        let world = SimWorld(seed: 11, macs: [SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1, running: true)])
        let truth = world.groundTruth
        world.step(.userEdit(mac: .A, unit: "UseIceBar"))
        world.advance(seconds: 1)
        world.step(.userEdit(mac: .B, unit: "ShowOnHover"))
        #expect(truth.globallyLost().isEmpty)
        // Both push without reading: B's file, pushed a second after A's, replaces A's in every replica.
        world.advance(seconds: 6)
        #expect(truth.globallyLost().isEmpty)
        let prompt = try #require(world.brain(of: .A).openPrompt)
        #expect(prompt.title == "Settings changed on another Mac")
        #expect(truth.prompts.count == 2)
        // A restarts: it applies B's file with remove-missing and A's own change is gone everywhere.
        world.step(.answer(mac: .A, .use))
        #expect(truth.globallyLost() == ["u1@UseIceBar"])
        #expect(truth.prompts.last { $0.mac == .A }?.answer == .use)
        let changeB = try #require(truth.change(forToken: "u2@ShowOnHover"))
        #expect(truth.past(ofMac: .A).contains(changeB.id))
        #expect(truth.origin(of: "u1@UseIceBar") == .user)
    }

    @Test("The world records destruction by non-sync events as such")
    func worldClassifiesNonSyncDestruction() {
        let world = SimWorld(seed: 12, macs: [SimMacSpec(.A, .beta1, running: true)])
        world.step(.userEdit(mac: .A, unit: "UseIceBar"))
        world.advance(seconds: 6)
        // The defaults holder and the file holder are both destroyed by non-sync events.
        world.step(.provider(.deleteFolder()))
        world.advance(seconds: 1)
        #expect(world.groundTruth.globallyLost().isEmpty)
        world.step(.reinstall(mac: .A))
        #expect(world.groundTruth.globallyLost().isEmpty)
    }

    @Test("Generations are tracked per Mac and an OS upgrade changes them")
    func generationsInTheWorld() {
        let world = SimWorld(seed: 13, macs: [SimMacSpec(.A, .redesign, generation: 26), SimMacSpec(.B, .redesign, generation: 27)])
        #expect(world.groundTruth.generation(of: .A) == 26)
        #expect(world.groundTruth.generation(of: .B) == 27)
        world.step(.upgradeOS(mac: .A))
        #expect(world.groundTruth.generation(of: .A) == 27)
    }
}
