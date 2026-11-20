//
//  ReleaseHold27.swift
//  holzBar
//

/// Counts the holds that release every concealment at once (macOS 27).
///
/// While MenuBarAgent hides an application it cannot name, only an empty assertion lets its item
/// draw (``UnnameableApps27``). A hold turns the concealment target into the empty one for as
/// long as any hold is live. Holds nest: the target stays empty until the last one ends.
///
/// A hold that is never ended would leave every hidden item drawn, so the app side goes through
/// ``withHold(begin:end:body:)`` only, which ends it exactly once on every path.
nonisolated struct ReleaseHold27: Equatable, Sendable {
    /// The holds live now.
    private(set) var count = 0

    /// Whether any hold is live.
    var isHeld: Bool {
        // swiftlint:disable:next empty_count
        count > 0
    }

    /// Starts one hold.
    mutating func begin() {
        count += 1
    }

    /// Ends one hold.
    ///
    /// - Returns: Whether a hold was live to end; `false` means the call was unbalanced and the
    ///   count stays 0.
    @discardableResult
    mutating func end() -> Bool {
        // swiftlint:disable:next empty_count
        guard count > 0 else {
            return false
        }
        count -= 1
        return true
    }

    /// The concealment target to apply: empty while held, otherwise `sets` unchanged.
    func target(_ sets: [Set<String>]) -> [Set<String>] {
        isHeld ? [] : sets
    }

    /// Runs `body` with a hold taken by `begin` and ends it exactly once, however `body` ends:
    /// a normal return, an early return, a thrown error or a cancelled task.
    ///
    /// Every app-side hold goes through this, so the counter in the concealer can never leak.
    ///
    /// - Parameters:
    ///   - begin: Takes the hold and answers whether its release landed.
    ///   - end: Ends the hold taken by `begin`.
    ///   - body: Gets the answer of `begin`; it runs whether or not the release landed.
    static func withHold<Result>(
        begin: () async -> Bool,
        end: () -> Void,
        body: (Bool) async throws -> Result
    ) async rethrows -> Result {
        let landed = await begin()
        defer { end() }
        return try await body(landed)
    }
}
