import Foundation

/// The simulator's only source of randomness: xoshiro256** seeded through SplitMix64.
///
/// Nothing in the simulation may call the system generator, the current-date initializer or Swift's randomized
/// `hashValue`: one seed reproduces one trace (analysis section 5.1, principle 3).
struct SimRandom: Sendable, Equatable {
    /// The seed this stream was created from. `fork(_:)` derives from it, never from the
    /// running state, so forks do not depend on how much the parent has been used.
    let seed: UInt64
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    init(seed: UInt64) {
        self.seed = seed
        var splitMix = seed
        s0 = Self.splitMix64(&splitMix)
        s1 = Self.splitMix64(&splitMix)
        s2 = Self.splitMix64(&splitMix)
        s3 = Self.splitMix64(&splitMix)
    }

    private static func splitMix64(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private static func rotateLeft(_ value: UInt64, _ count: UInt64) -> UInt64 {
        (value << count) | (value >> (64 - count))
    }

    /// The next 64 random bits.
    mutating func next() -> UInt64 {
        let result = Self.rotateLeft(s1 &* 5, 7) &* 9
        let shifted = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= shifted
        s3 = Self.rotateLeft(s3, 45)
        return result
    }

    /// A uniformly distributed value in `[0, 1)` with 53 bits of precision.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// A uniformly distributed integer in the range (modulo bias is irrelevant for a simulator).
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound) &+ 1
        if width == 0 { return Int(truncatingIfNeeded: next()) }
        return range.lowerBound + Int(next() % width)
    }

    /// `true` with probability `p`. A probability of 0 or less never draws; 1 or more always does.
    mutating func chance(_ probability: Double) -> Bool {
        if probability <= 0 { return false }
        if probability >= 1 { return true }
        return unit() < probability
    }

    /// A uniformly chosen element. The collection must not be empty.
    mutating func pick<Element>(_ elements: [Element]) -> Element {
        precondition(!elements.isEmpty, "pick from an empty collection")
        return elements[int(in: 0...(elements.count - 1))]
    }

    /// A heavy-tailed (Pareto, shape 1.2) delay in milliseconds whose median is the argument.
    /// Capped at 30 days, so "never during the run" is a long delay, not an overflow.
    mutating func heavyTailedDelay(medianMilliseconds: Int64) -> Int64 {
        let shape = 1.2
        let minimum = Double(max(medianMilliseconds, 1)) / pow(2.0, 1.0 / shape)
        let draw = max(1.0 - unit(), 1e-12)
        let delay = minimum / pow(draw, 1.0 / shape)
        let cap = Double(30 * 24 * 3600 * 1000)
        return Int64(min(delay, cap))
    }

    /// An independent stream derived from the seed and a stable FNV-1a hash of the label.
    func fork(_ label: String) -> SimRandom {
        SimRandom(seed: (seed &* 0x9E37_79B9_7F4A_7C15) ^ Self.fnv1a(label))
    }

    /// 64-bit FNV-1a over the UTF-8 bytes. Stable across runs, unlike `hashValue`.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
