import Foundation
import Testing

@Suite("SimProvider")
struct SimProviderTests {
    private let path = "holzBar/Settings.plist"
    private let day: Int64 = 24 * 3600 * 1000
    private let allMacs: [SimMacName] = [.A, .B, .C]

    private func provider(_ policy: SimFaultPolicy = .ideal, seed: UInt64 = 1, macs: [SimMacName]? = nil) -> SimProvider {
        var provider = SimProvider(policy: policy, random: SimRandom(seed: seed))
        for mac in macs ?? allMacs { provider.ensureReplica(for: mac) }
        return provider
    }

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    private func context(_ provider: SimProvider, mac: SimMacName = .B, now: Int64 = 0, timeout: Int64 = 5_000) -> SimMacContext {
        let state = SimMacState(
            name: mac, version: .redesign, markers: SimIdentityMarkers(mac: mac), uid: 501, generation: 26,
            random: SimRandom(seed: 1)
        )
        var state2 = state
        state2.enabled = true
        state2.folderID = "F1"
        return SimMacContext(
            mac: mac, state: state2, wallClock: Date(timeIntervalSince1970: 0), replica: provider.replica(of: mac),
            globalNow: now, ioTimeoutMilliseconds: timeout
        )
    }

    private func present(_ provider: SimProvider, _ mac: SimMacName, _ path: String) -> String? {
        if case .present(let data) = provider.replica(of: mac).entry(path) { return String(decoding: data, as: UTF8.self) }
        return nil
    }

    // MARK: Delivery

    @Test("A write is present at once for the writer and arrives later at the others")
    func delayedDelivery() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 10_000))
        _ = p.write(from: .A, path: path, data: bytes("one"))
        #expect(present(p, .A, path) == "one")
        #expect(p.replica(of: .B).entry(path) == .absent)
        #expect(p.nextDeliveryTime != nil)
        let notices = p.deliverDue(until: 31 * day)
        #expect(Set(notices.map(\.mac)) == [.B, .C])
        #expect(present(p, .B, path) == "one")
        #expect(present(p, .C, path) == "one")
        #expect(p.nextDeliveryTime == nil)
    }

    @Test("An offline Mac neither sends nor receives until it is back")
    func offlineWindows() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000))
        p.setOffline(.B, until: 500_000)
        _ = p.write(from: .A, path: path, data: bytes("one"))
        _ = p.deliverDue(until: 400_000)
        #expect(p.replica(of: .B).entry(path) == .absent)
        _ = p.deliverDue(until: 31 * day)
        #expect(present(p, .B, path) == "one")

        var q = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000))
        q.setOffline(.A, until: 100_000)
        _ = q.write(from: .A, path: path, data: bytes("late"))
        _ = q.deliverDue(until: 99_999)
        #expect(q.replica(of: .C).entry(path) == .absent)
        _ = q.deliverDue(until: 31 * day)
        #expect(present(q, .C, path) == "late")
    }

    @Test("Two writes delivered out of order end at the later content when coalescing is on")
    func outOfOrderEndsAtLaterContent() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000, coalesceProbability: 1), macs: [.A, .B])
        _ = p.write(from: .A, path: path, data: bytes("one"))
        p.now = 1_000
        _ = p.write(from: .A, path: path, data: bytes("two"))
        p.retime(version: 2, target: .B, to: 2_000)
        p.retime(version: 1, target: .B, to: 5_000)
        _ = p.deliverDue(until: 3_000)
        #expect(present(p, .B, path) == "two")
        _ = p.deliverDue(until: 10_000)
        #expect(present(p, .B, path) == "two")
        #expect(p.drainLog().contains { $0.hasPrefix("stale B") })
    }

    @Test("Without coalescing a stale delivery overwrites newer content")
    func staleDeliveryWithoutCoalescing() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000, coalesceProbability: 0), macs: [.A, .B])
        _ = p.write(from: .A, path: path, data: bytes("one"))
        p.now = 1_000
        _ = p.write(from: .A, path: path, data: bytes("two"))
        p.retime(version: 2, target: .B, to: 2_000)
        p.retime(version: 1, target: .B, to: 5_000)
        _ = p.deliverDue(until: 10_000)
        #expect(present(p, .B, path) == "one")
    }

    @Test("Due deliveries of one path coalesce to the newest")
    func coalescingSkipsIntermediates() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000, coalesceProbability: 1), macs: [.A, .B])
        _ = p.write(from: .A, path: path, data: bytes("one"))
        _ = p.write(from: .A, path: path, data: bytes("two"))
        p.retime(version: 1, target: .B, to: 2_000)
        p.retime(version: 2, target: .B, to: 2_500)
        _ = p.deliverDue(until: 3_000)
        #expect(present(p, .B, path) == "two")
        #expect(p.drainLog().contains { $0.hasPrefix("coalesce B") })
    }

    @Test("A duplicate delivery changes nothing visible")
    func duplicateDelivery() {
        var plain = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000))
        var doubled = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000, duplicateProbability: 1))
        for index in 0..<2 {
            var p = index == 0 ? plain : doubled
            _ = p.write(from: .A, path: path, data: bytes("one"))
            p.now = 5_000
            _ = p.write(from: .A, path: path, data: bytes("two"))
            _ = p.deliverDue(until: 31 * day)
            #expect(present(p, .B, path) == "two")
            #expect(present(p, .C, path) == "two")
            #expect(p.nextDeliveryTime == nil)
            if index == 0 { plain = p } else { doubled = p }
        }
        #expect(plain.replica(of: .B).entries == doubled.replica(of: .B).entries)
    }

    @Test("Delivered content can arrive as a dataless placeholder and a requested download makes it present later")
    func datalessAndDownload() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000, datalessOnArrivalProbability: 1))
        _ = p.write(from: .A, path: path, data: bytes("one"))
        _ = p.deliverDue(until: 31 * day)
        #expect(p.replica(of: .B).entry(path) == .dataless(bytes("one")))
        var ctx = context(p, mac: .B, now: p.now)
        #expect(ctx.read(path, maximumBytes: 1 << 20) == .notLocal)
        ctx.requestDownload(path)
        #expect(ctx.actions == [.requestDownload(folder: "F1", path: path)])
        p.requestDownload(path: path, mac: .B)
        #expect(present(p, .B, path) == nil)
        _ = p.deliverDue(until: p.now + 31 * day)
        #expect(present(p, .B, path) == "one")
        var after = context(p, mac: .B, now: p.now)
        if case .data(let data, let version) = after.read(path, maximumBytes: 1 << 20) {
            #expect(data == bytes("one"))
            #expect(version == 1)
        } else {
            Issue.record("the downloaded file should be readable")
        }
    }

    @Test("Evict turns a present file into dataless on one Mac")
    func evictOneMac() {
        var p = provider()
        _ = p.write(from: .A, path: path, data: bytes("one"))
        _ = p.deliverDue(until: 0)
        p.evict(path: path, mac: .B)
        #expect(p.replica(of: .B).entry(path) == .dataless(bytes("one")))
        #expect(present(p, .C, path) == "one")
        var ctx = context(p, mac: .B)
        #expect(ctx.read(path, maximumBytes: 1 << 20) == .notLocal)
    }

    // MARK: Concurrent writes

    private func concurrent(_ style: SimConflictStyle) -> SimProvider {
        var p = provider(SimFaultPolicy(
            medianDelayMilliseconds: 1_000, conflictCopyProbability: 1, conflictStyles: [style]
        ))
        _ = p.write(from: .A, path: path, data: bytes("from-A"))
        p.now = 100
        _ = p.write(from: .B, path: path, data: bytes("from-B"))
        _ = p.deliverDue(until: 31 * day)
        return p
    }

    private func siblings(_ p: SimProvider, _ mac: SimMacName) -> [String] {
        p.replica(of: mac).entries.keys.sorted().filter { $0 != path }
    }

    @Test("Dropbox keeps the earlier content as a conflicted copy named after its computer")
    func dropboxConflict() {
        let p = concurrent(.dropbox)
        for mac in allMacs {
            #expect(present(p, mac, path) == "from-B")
            let copies = siblings(p, mac)
            #expect(copies.count == 1)
            #expect(copies.first?.hasPrefix("holzBar/Settings (MARKER-NAME-A's conflicted copy ") == true)
            #expect(copies.first?.hasSuffix(").plist") == true)
            #expect(copies.first.flatMap { present(p, mac, $0) } == "from-A")
        }
    }

    @Test("OneDrive names the copy with the computer name marker")
    func oneDriveConflict() {
        let p = concurrent(.oneDrive)
        for mac in allMacs {
            #expect(present(p, mac, path) == "from-B")
            #expect(present(p, mac, "holzBar/Settings-MARKER-NAME-A.plist") == "from-A")
        }
        #expect(SimProvider.conflictCopyPath(
            for: path, style: .oneDrive, computerName: "MARKER-NAME-A", loserMac: .A, globalNow: 0
        ).contains("MARKER-NAME-A"))
    }

    @Test("Nextcloud keeps the conflicted copy only on the losing Mac")
    func nextcloudConflict() {
        let p = concurrent(.nextcloud)
        let onLoser = siblings(p, .A)
        #expect(onLoser.count == 1)
        #expect(onLoser.first?.hasPrefix("holzBar/Settings (conflicted copy ") == true)
        #expect(siblings(p, .B).isEmpty)
        #expect(siblings(p, .C).isEmpty)
        #expect(present(p, .A, path) == "from-B")
        #expect(onLoser.first.flatMap { present(p, .A, $0) } == "from-A")
    }

    @Test("Syncthing propagates a sync-conflict copy")
    func syncthingConflict() {
        let p = concurrent(.syncthing)
        for mac in allMacs {
            let copies = siblings(p, mac)
            #expect(copies.count == 1)
            #expect(copies.first?.hasPrefix("holzBar/Settings.sync-conflict-") == true)
            #expect(copies.first?.hasSuffix("-AAAAAAA.plist") == true)
            #expect(present(p, mac, path) == "from-B")
        }
    }

    @Test("iCloud keeps a per-device winner and an unresolved version on every Mac")
    func iCloudPerDeviceWinner() {
        let p = concurrent(.perDeviceWinner)
        #expect(present(p, .A, path) == "from-A")
        #expect(present(p, .B, path) == "from-B")
        #expect(present(p, .C, path) == "from-B")
        func versions(_ mac: SimMacName) -> [String] {
            var ctx = context(p, mac: mac, now: p.now)
            return ctx.conflictVersions(of: path).map { String(decoding: $0.data, as: UTF8.self) }
        }
        #expect(versions(.A) == ["from-B"])
        #expect(versions(.B) == ["from-A"])
        #expect(versions(.C) == ["from-A"])
        for mac in allMacs { #expect(siblings(p, mac).isEmpty) }
        var ctx = context(p, mac: .A, now: p.now)
        ctx.resolveConflictVersions(of: path)
        #expect(ctx.conflictVersions(of: path).isEmpty)
    }

    @Test("SMB lets the last writer win and keeps no copy")
    func lastWriterWinsConflict() {
        let p = concurrent(.lastWriterWins)
        for mac in allMacs {
            #expect(present(p, mac, path) == "from-B")
            #expect(siblings(p, mac).isEmpty)
        }
    }

    @Test("Writes by a Mac that has seen the other write do not conflict")
    func informedWriteIsNoConflict() {
        var p = provider(SimFaultPolicy(
            medianDelayMilliseconds: 1_000, conflictCopyProbability: 1, conflictStyles: [.dropbox]
        ))
        _ = p.write(from: .A, path: path, data: bytes("from-A"))
        _ = p.deliverDue(until: 31 * day)
        _ = p.write(from: .B, path: path, data: bytes("from-B"))
        _ = p.deliverDue(until: 62 * day)
        for mac in allMacs {
            #expect(present(p, mac, path) == "from-B")
            #expect(siblings(p, mac).isEmpty)
        }
    }

    // MARK: Partial exposure, stalls, unmount

    @Test("ExposePartial shows truncated bytes until the window ends")
    func partialExposure() {
        var p = provider()
        _ = p.write(from: .A, path: path, data: bytes("0123456789"))
        _ = p.deliverDue(until: 0)
        p.exposePartial(path: path, mac: .B, until: 5_000)
        if case .data(let data, _) = p.replica(of: .B).read(path, maximumBytes: 1 << 20) {
            #expect(data.count < 10)
            #expect(data.count > 0)
        } else {
            Issue.record("a partial file reads as truncated bytes")
        }
        #expect(present(p, .C, path) == "0123456789")
        p.settle(at: 4_999)
        #expect(present(p, .B, path) == nil)
        p.settle(at: 5_000)
        #expect(present(p, .B, path) == "0123456789")
    }

    @Test("A short stall delays the caller and a long or endless stall times it out")
    func stalls() {
        var p = provider()
        _ = p.write(from: .A, path: path, data: bytes("one"))
        _ = p.deliverDue(until: 0)
        p.stall(mac: .B, until: 3_000)
        var shortStall = context(p, mac: .B, now: 0)
        if case .data(let data, _) = shortStall.read(path, maximumBytes: 1 << 20) { #expect(data == bytes("one")) } else {
            Issue.record("a stall shorter than the bound only delays")
        }
        #expect(shortStall.blockedMilliseconds == 3_000)
        #expect(shortStall.write(path, bytes("two")) == .written)

        p.stall(mac: .B, until: 20_000)
        var longStall = context(p, mac: .B, now: 0)
        #expect(longStall.read(path, maximumBytes: 1 << 20) == .timedOut)
        #expect(longStall.write(path, bytes("two")) == .timedOut)
        #expect(longStall.actions.isEmpty)
        #expect(longStall.list("holzBar") == .timedOut)
        #expect(longStall.blockedMilliseconds == 15_000)

        p.stall(mac: .B, until: Int64.max)
        var hung = context(p, mac: .B, now: 1_000_000)
        #expect(hung.read(path, maximumBytes: 1 << 20) == .timedOut)
        p.stall(mac: .B, until: 20_000)
        p.settle(at: 20_000)
        var recovered = context(p, mac: .B, now: 20_000)
        if case .data = recovered.read(path, maximumBytes: 1 << 20) {} else { Issue.record("the stall has ended") }
        #expect(recovered.blockedMilliseconds == 0)
    }

    @Test("Unmount hides the folder, records write attempts as violations and mount restores it")
    func unmountAndMount() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000))
        _ = p.write(from: .A, path: path, data: bytes("one"))
        _ = p.deliverDue(until: 31 * day)
        p.unmount(.B)
        var ctx = context(p, mac: .B, now: p.now)
        #expect(ctx.read(path, maximumBytes: 1 << 20) == .notMounted)
        #expect(ctx.list("holzBar") == .notMounted)
        #expect(ctx.write(path, bytes("x")) == .notMounted)
        #expect(ctx.actions == [.write(folder: "F1", path: path, data: bytes("x"))])
        #expect(p.write(from: .B, path: path, data: bytes("x")) == .notMounted)
        #expect(p.violations.count == 1)
        #expect(p.violations.first?.mac == .B)
        #expect(present(p, .B, path) == "one")

        _ = p.write(from: .A, path: path, data: bytes("two"))
        _ = p.deliverDue(until: p.now + 31 * day)
        #expect(present(p, .B, path) == "one")
        p.mount(.B)
        _ = p.deliverDue(until: p.now + 31 * day)
        #expect(present(p, .B, path) == "two")
    }

    // MARK: Restore, delete, foreign

    @Test("Restore puts back earlier content, Delete removes a file and DeleteFolder the whole folder")
    func restoreAndDelete() {
        var p = provider(SimFaultPolicy(medianDelayMilliseconds: 1_000))
        _ = p.write(from: .A, path: path, data: bytes("one"))
        p.now = 10_000
        _ = p.write(from: .A, path: path, data: bytes("two"))
        _ = p.write(from: .A, path: "holzBar/Macs/a.plist", data: bytes("device"))
        _ = p.write(from: .A, path: "other/keep.txt", data: bytes("keep"))
        _ = p.deliverDue(until: 31 * day)
        #expect(present(p, .C, path) == "two")
        p.restore(path: path, version: 1)
        _ = p.deliverDue(until: p.now + 31 * day)
        for mac in allMacs { #expect(present(p, mac, path) == "one") }

        p.delete(path: path)
        _ = p.deliverDue(until: p.now + 31 * day)
        for mac in allMacs { #expect(p.replica(of: mac).entry(path) == .absent) }
        #expect(present(p, .B, "holzBar/Macs/a.plist") == "device")

        p.deleteFolder()
        _ = p.deliverDue(until: p.now + 31 * day)
        for mac in allMacs {
            #expect(p.replica(of: mac).entry("holzBar/Macs/a.plist") == .absent)
            #expect(p.replica(of: mac).list("holzBar").isEmpty)
        }
        #expect(present(p, .B, "other/keep.txt") == "keep")
    }

    @Test("Foreign writes a symbolic link, oversize bytes, a truncated plist or a type-swapped plist")
    func foreignBytes() throws {
        var p = provider()
        let good: [String: Any] = ["modified": Date(timeIntervalSince1970: 5), "deviceID": "X", "settings": [String: Any]()]
        let goodData = try PropertyListSerialization.data(fromPropertyList: good, format: .xml, options: 0)
        _ = p.write(from: .A, path: path, data: goodData)
        _ = p.deliverDue(until: 0)

        p.foreign(path: path, kind: .truncatedPlist)
        _ = p.deliverDue(until: 0)
        if case .data(let data, _) = p.replica(of: .B).read(path, maximumBytes: 1 << 20) {
            #expect(data.count < goodData.count)
            #expect((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) == nil)
        } else {
            Issue.record("truncated bytes are readable")
        }

        p.foreign(path: path, kind: .typeSwappedPlist)
        _ = p.deliverDue(until: 0)
        if case .data(let data, _) = p.replica(of: .B).read(path, maximumBytes: 1 << 20) {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            #expect(object?["settings"] is String)
            #expect(object?["modified"] is String)
        } else {
            Issue.record("a type-swapped plist is readable")
        }

        p.foreign(path: path, kind: .oversize)
        _ = p.deliverDue(until: 0)
        if case .tooLarge(let size) = p.replica(of: .B).read(path, maximumBytes: 1 << 20) {
            #expect(size > 1 << 20)
        } else {
            Issue.record("oversize bytes exceed the bound")
        }

        p.foreign(path: path, kind: .symbolicLink)
        _ = p.deliverDue(until: 0)
        for mac in allMacs { #expect(p.replica(of: mac).read(path, maximumBytes: 1 << 20) == .symbolicLink) }
    }

    // MARK: Presets and determinism

    @Test("There are seven presets and only SMB emits no folder-change signals")
    func presets() {
        #expect(SimProviderPreset.allCases.count == 7)
        for preset in SimProviderPreset.allCases {
            #expect(preset.policy.signalsFolderChanges == (preset != .smb))
        }
        #expect(SimProviderPreset.iCloud.policy.conflictStyles == [.perDeviceWinner])
        #expect(SimProviderPreset.dropbox.policy.conflictStyles == [.dropbox])
        #expect(SimProviderPreset.oneDrive.policy.conflictStyles == [.oneDrive])
        #expect(SimProviderPreset.nextcloud.policy.conflictStyles == [.nextcloud])
        #expect(SimProviderPreset.syncthing.policy.conflictStyles == [.syncthing])
        #expect(SimProviderPreset.smb.policy.conflictStyles.isEmpty)
        #expect(Set(SimProviderPreset.hostile.policy.conflictStyles) == Set(SimConflictStyle.allCases))
        #expect(SimProviderPreset.syncthing.policy.datalessOnArrivalProbability == 0)
        #expect(SimProviderPreset.smb.policy.rates.unmount > 0)
    }

    @Test("The hostile provider is deterministic per seed")
    func hostileIsDeterministic() {
        func run(seed: UInt64) -> [String] {
            var p = provider(SimProviderPreset.hostile.policy, seed: seed)
            for step in 0..<20 {
                p.now = Int64(step) * 2_000
                _ = p.write(from: allMacs[step % 3], path: path, data: bytes("w\(step)"))
                _ = p.deliverDue(until: p.now)
            }
            _ = p.deliverDue(until: 40 * day)
            return p.drainLog()
        }
        #expect(run(seed: 5) == run(seed: 5))
        #expect(run(seed: 5) != run(seed: 6))
    }

    // MARK: Inside the world

    @Test("The world routes provider events and raises signals only when the provider emits them")
    func worldRoutesProviderEvents() throws {
        func prompted(signals: Bool) -> Bool {
            let policy = SimFaultPolicy(medianDelayMilliseconds: 1_000, signalsFolderChanges: signals)
            let world = SimWorld(seed: 3, macs: [
                SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1, running: true),
            ], policy: policy)
            world.advance(seconds: 1)
            world.step(.userEdit(mac: .A, unit: "ShowOnHover"))
            world.advance(seconds: 3 * 24 * 3600)
            return world.brain(of: .B).openPrompt != nil
        }
        #expect(prompted(signals: true))
        #expect(!prompted(signals: false))

        let world = SimWorld(seed: 4, macs: [SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1)])
        #expect(world.replica(of: .B).entry(SimMacBeta1.filePath) != .absent)
        world.step(.provider(.deleteFolder()))
        world.advance(seconds: 1)
        #expect(world.replica(of: .B).entry(SimMacBeta1.filePath) == .absent)
        world.step(.provider(.unmount(mac: .A)))
        world.step(.userEdit(mac: .A, unit: "ShowOnHover"))
        world.advance(seconds: 6)
        #expect(world.violations.count == 1)
        world.step(.provider(.mount(mac: .A)))
        world.step(.provider(.foreign(path: SimMacBeta1.filePath, kind: .garbage)))
        world.advance(seconds: 1)
        #expect(world.replica(of: .B).entry(SimMacBeta1.filePath) == .present(Data("garbage".utf8)))
    }

    // MARK: Beta2

    @Test("A beta2 Mac never touches the folder and its load-time writers run at every launch")
    func beta2LoadTimeWriters() throws {
        let hotkeys = SimValue.dictionary([
            "a": .dictionary(["combo": .int(1), "token": .string("u1@Hotkeys/a")]),
            "b": .dictionary(["combo": .int(1), "token": .string("u2@Hotkeys/b")]),
            "c": .dictionary(["combo": .int(2), "token": .string("u3@Hotkeys/c")]),
        ])
        var spec = SimMacSpec(.A, .beta2)
        spec.defaults = [
            "Hotkeys": hotkeys,
            "ItemSpacingOffset": .int(99),
            "RehideInterval": .int(0),
            "MenuBarAppearanceConfigurationV2": .data(SimMacBeta2.userEncodedJSON(token: "u4@MenuBarAppearanceConfigurationV2")),
        ]
        let loaded = SimWorld(seed: 9, macs: [spec, SimMacSpec(.B, .beta1)])
        let originalAppearance = loaded.defaults(of: .A)["MenuBarAppearanceConfigurationV2"]
        loaded.step(.launch(mac: .A))
        let defaults = loaded.defaults(of: .A)
        guard case .dictionary(let kept)? = defaults["Hotkeys"] else {
            Issue.record("hotkeys stay a dictionary")
            return
        }
        #expect(kept.keys.sorted() == ["a", "c"])
        #expect(defaults["ItemSpacingOffset"] == .int(16))
        #expect(defaults["RehideInterval"] == .int(1))
        guard case .data(let encoded)? = defaults["MenuBarAppearanceConfigurationV2"] else {
            Issue.record("appearance stays data")
            return
        }
        #expect(defaults["MenuBarAppearanceConfigurationV2"] != originalAppearance)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["token"] as? String == "u4@MenuBarAppearanceConfigurationV2")
        #expect(object["tint"] as? String == "none")
        #expect(object["futureField"] == nil)
        #expect(loaded.trace.contains { $0.hasSuffix("AUTO A Hotkeys changed=true") })
        #expect(loaded.trace.contains { $0.hasSuffix("AUTO A ItemSpacingOffset changed=true") })

        loaded.step(.quit(mac: .A))
        loaded.step(.launch(mac: .A))
        #expect(loaded.trace.contains { $0.hasSuffix("AUTO A ItemSpacingOffset changed=false") })
        #expect(loaded.replica(of: .A).entries.isEmpty)
    }
}
