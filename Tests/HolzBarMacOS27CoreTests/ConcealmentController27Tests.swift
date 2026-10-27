import Testing
@testable import HolzBarMacOS27Core

/// Simulates MenuBarAgent: an item shows if any live assertion allows it. A numbered system
/// item `n` stands for the entry `system-item:n`.
@MainActor
final class FakeConcealmentBackend: ConcealmentBackend27 {
    final class Token: ConcealmentToken27 {
        let allowed: Set<String>
        let allowedNumbers: [Int]
        init(allowed: Set<String>, allowedNumbers: [Int]) {
            self.allowed = allowed
            self.allowedNumbers = allowedNumbers
        }
    }

    struct Rejected: Error {}

    var universe: Set<String>
    var rejectNextActivation = false
    private(set) var liveTokens = [Token]()
    private(set) var activationCount = 0
    /// What the bar conceals after every activation and invalidation.
    private(set) var history = [Set<String>]()

    init(universe: Set<String>) {
        self.universe = universe
    }

    var concealed: Set<String> {
        guard !liveTokens.isEmpty else { return [] }
        let allowed = liveTokens.reduce(into: Set<String>()) { result, token in
            result.formUnion(token.allowed)
            result.formUnion(token.allowedNumbers.map { SystemItems27.concealedKeyPrefix + String($0) })
        }
        return universe.subtracting(allowed)
    }

    func activate(allowedBundleIDs: [String], allowedSystemItems: [Int]) async throws -> ConcealmentToken27 {
        if rejectNextActivation {
            rejectNextActivation = false
            throw Rejected()
        }
        activationCount += 1
        let token = Token(allowed: Set(allowedBundleIDs), allowedNumbers: allowedSystemItems)
        liveTokens.append(token)
        history.append(concealed)
        return token
    }

    func invalidate(_ token: ConcealmentToken27) {
        liveTokens.removeAll { $0 === token }
        history.append(concealed)
    }
}

@Suite("ConcealmentController27")
@MainActor
struct ConcealmentController27Tests {
    let running: Set<String> = ["visible.app", "hidden.app", "always.app"]
    let allHidden: [Set<String>] = [["hidden.app", "always.app"]]
    let hiddenRevealed: [Set<String>] = [["always.app"]]

    @Test("Hiding conceals the target set")
    func hiding() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(controller.isActive)
    }

    @Test("Revealing the hidden section never exposes always-hidden apps")
    func revealing() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        try await controller.apply(target: hiddenRevealed, running: running)
        #expect(backend.concealed == ["always.app"])
        #expect(backend.history.allSatisfy { $0.contains("always.app") })
    }

    @Test("Hiding again never exposes always-hidden apps")
    func hidingAgain() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        try await controller.apply(target: hiddenRevealed, running: running)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.history.allSatisfy { $0.contains("always.app") })
    }

    @Test("Re-applying the same state does not churn assertions")
    func noChurn() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.activationCount == 1)
    }

    @Test("A launched app is allowed without exposing concealed apps")
    func launchedApp() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(["new.app"]))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed.contains("new.app"))
        try await controller.apply(target: allHidden, running: running.union(["new.app"]))
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.history.allSatisfy { $0.isSuperset(of: ["hidden.app", "always.app"]) })
    }

    @Test("A rejected activation keeps the previous state")
    func rejected() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        backend.rejectNextActivation = true
        await #expect(throws: FakeConcealmentBackend.Rejected.self) {
            try await controller.apply(target: hiddenRevealed, running: running)
        }
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.liveTokens.count == 1)
        // What is live, not what was asked for.
        #expect(controller.liveConcealed == ["hidden.app", "always.app"])
        controller.releaseAll()
        #expect(controller.liveConcealed.isEmpty)
    }

    @Test("Releasing restores every item")
    func releasing() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        controller.releaseAll()
        #expect(backend.concealed.isEmpty)
        #expect(!controller.isActive)
    }

    // MARK: Hidden system items

    let systemItems: Set<String> = Set(SystemItem27.allCases.map { SystemItems27.concealedKey(for: $0) })

    @Test("A hidden system item is concealed by one assertion and nothing else is")
    func systemItemAlone() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(systemItems))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: [["system-item:2"]], running: running)
        #expect(backend.concealed == ["system-item:2"])
        #expect(backend.activationCount == 1)
        #expect(controller.liveConcealed == ["system-item:2"])
    }

    @Test("An app and a system item are concealed together by one assertion")
    func appAndSystemItem() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(systemItems))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: [["hidden.app", "system-item:8"]], running: running)
        #expect(backend.concealed == ["hidden.app", "system-item:8"])
        #expect(backend.activationCount == 1)
    }

    @Test("Applying nothing afterwards restores the app and the system item")
    func restoring() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(systemItems))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: [["hidden.app", "system-item:2"]], running: running)
        try await controller.apply(target: [], running: running)
        #expect(backend.concealed.isEmpty)
        #expect(!controller.isActive)
    }

    @Test("Revealing the hidden section brings the system item back")
    func revealingBringsTheSystemItemBack() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(systemItems))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: [["hidden.app", "always.app", "system-item:2"]], running: running)
        try await controller.apply(target: hiddenRevealed, running: running)
        #expect(backend.concealed == ["always.app"])
    }

    @Test("Applying the same system target twice does not activate again")
    func systemTargetNoChurn() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(systemItems))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: [["system-item:6"]], running: running)
        try await controller.apply(target: [["system-item:6"]], running: running)
        #expect(backend.activationCount == 1)
    }

    @Test("Without a hidden system item every number stays allowed")
    func noSystemItemHidden() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(systemItems))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.liveTokens.first?.allowedNumbers == Array(SystemItems27.allowed))
    }
}
