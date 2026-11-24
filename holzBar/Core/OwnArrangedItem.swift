//
//  OwnArrangedItem.swift
//  holzBar
//

import Foundation

/// Which status items are holzBar's own items that the bar, Layout and the Shelf arrange like an
/// app's item: a widget and a Dock badges item.
///
/// Such an item is shown in Layout, moved between sections and drawn in the Shelf like another
/// app's item, yet it is holzBar's: it is never captured, concealed by an assertion, counted as a
/// third-party item, offered by Making room or recorded as a known application. Every site that
/// asks must ask here; a later kind of item joins here, never at a site.
nonisolated enum OwnArrangedItem {
    /// Whether a name is the autosave name of one of holzBar's own arranged items.
    static func isAutosaveName(_ name: String) -> Bool {
        WidgetDefinition.isAutosaveName(name) || DockBadgeItemName.isAutosaveName(name)
    }
}
