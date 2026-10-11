//
//  WidgetScriptSharing.swift
//  holzBar
//

import Foundation

/// Which script widgets take over the result of a run that another widget started.
///
/// The runner serialises a script by its name and answers "busy" to a second caller, so two
/// widgets bound to one script (a narrow and a wide one) asked together would leave the second
/// with an en dash for as long as nothing asked it again (WR-03). The turned-away widget waits
/// for the run to end and takes over its result: the script is the same and so is the event
/// (`widget-refresh`), so the line is the same, and no second run is spent.
nonisolated enum WidgetScriptSharing {
    /// The widgets that take over the result of a run of `name` that `finished` started.
    ///
    /// - Parameters:
    ///   - name: The script that ran.
    ///   - finished: The widget whose run it was; it has its result already.
    ///   - waiting: The widgets that were turned away because their script was busy, each with
    ///     the script it is bound to now. A widget that was bound to another script since
    ///     waits for nothing here.
    /// - Returns: The widgets to give the result to, in a stable order.
    static func takingOver(script name: String, finished: UUID, waiting: [UUID: String]) -> [UUID] {
        waiting
            .filter { $0.key != finished && $0.value == name }
            .keys
            .sorted { $0.uuidString < $1.uuidString }
    }
}
