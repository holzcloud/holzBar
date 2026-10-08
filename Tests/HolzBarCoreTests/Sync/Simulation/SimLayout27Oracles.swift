import Foundation

/// The invariants of the macOS 27 families (A2 section 5.3 and 5.4), restricted to the units that only
/// generation-27 Macs author. Each reads the ground truth and the world's observations, never the engine's own
/// metadata, and is quiet in a world without a generation-27 Mac.
enum SimLayout27Oracles {
    static var all: [any SimOracle] { [] }
}
