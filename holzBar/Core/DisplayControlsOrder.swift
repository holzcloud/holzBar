//
//  DisplayControlsOrder.swift
//  holzBar
//

import Foundation

/// The order of the Display controls tab's cards.
///
/// The display the hub opened on comes first, so the controls the user most likely wants are
/// the first they see; the others keep the order macOS lists its screens in. The built-in
/// display is not placed first by any rule of its own.
nonisolated enum DisplayControlsOrder {
    /// The identifiers in the order the tab shows them: each identifier once at its first place,
    /// `first` in front when it is listed, every other in the order given. A `first` that is not
    /// listed, or `nil`, changes nothing.
    static func ordered(_ ids: [UInt32], first: UInt32?) -> [UInt32] {
        var seen = Set<UInt32>()
        let unique = ids.filter { seen.insert($0).inserted }
        guard let first, unique.contains(first) else {
            return unique
        }
        return [first] + unique.filter { $0 != first }
    }
}
