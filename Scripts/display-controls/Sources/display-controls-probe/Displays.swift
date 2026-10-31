//
//  Displays.swift
//  display-controls
//

import CoreGraphics
import DisplayProbeCore
import Foundation

/// One active display, by number only: the probe never prints a display's name.
struct DisplayInfo: Sendable {
    var id: UInt32
    var builtIn: Bool
    var main: Bool
    var width: Int
    var height: Int

    var line: String {
        ProbeLine.line("DISPLAY", [
            ("id", String(id)),
            ("builtIn", Report.yesNo(builtIn)),
            ("main", Report.yesNo(main)),
            ("width", String(width)),
            ("height", String(height)),
        ])
    }
}

enum Displays {
    /// The active displays, the main one first.
    static func list() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }
        return ids.prefix(Int(count)).map { id in
            DisplayInfo(
                id: id,
                builtIn: CGDisplayIsBuiltin(id) != 0,
                main: CGDisplayIsMain(id) != 0,
                width: CGDisplayPixelsWide(id),
                height: CGDisplayPixelsHigh(id)
            )
        }
        .sorted { $0.main && !$1.main }
    }
}
